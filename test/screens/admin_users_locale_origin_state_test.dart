import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/admin_screen.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import '../support/widget_polish_screenshot_font.dart';

const _selfId = 'admin-self';
const _literalUserId = 'user-0';
const _literalUsername = 'literal-user-0 原文 A';
const _coinUserId = 'user-1';

void main() {
  setUp(() => I18n.setLocale(AppLocale.zh));
  tearDown(() => I18n.setLocale(AppLocale.zh));

  testWidgets(
    'Users zh-en-zh keeps literal data, filters, selection, scroll, and an active draft',
    (tester) async {
      final fixture = await _mountUsers(tester, permissions: const ['users']);
      final module = _usersModule();
      final moduleElement = tester.element(module);
      final listScrollable = _userListScrollable();
      final scrollState = tester.state<ScrollableState>(listScrollable);
      final search = _searchField();

      await tester.enterText(search, 'alice 原文');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      final disabledChip = find.widgetWithText(ChoiceChip, '已禁用');
      await tester.ensureVisible(disabledChip);
      await tester.tap(disabledChip);
      await tester.pumpAndSettle();
      final sort = tester.widget<AppCompactDropdown<String>>(
        find.byType(AppCompactDropdown<String>),
      );
      sort.onChanged!.call('username_asc');
      await tester.pumpAndSettle();
      expect(fixture.userReads.last.queryParameters['q'], 'alice 原文');
      expect(fixture.userReads.last.queryParameters['status'], 'disabled');
      expect(fixture.userReads.last.queryParameters['sort'], 'username_asc');

      final selectedCard = find.byKey(
        const ValueKey('admin_user_mobile_card_$_literalUserId'),
      );
      await tester.ensureVisible(selectedCard);
      await tester.tap(
        find.descendant(of: selectedCard, matching: find.byType(Checkbox)),
      );
      await tester.pumpAndSettle();
      if (scrollState.position.maxScrollExtent > 60) {
        scrollState.position.jumpTo(60);
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.text(_literalUsername));
      await tester.pumpAndSettle();
      final listOffset = scrollState.position.pixels;
      expect(
        tester
            .widget<Checkbox>(
              find.descendant(
                of: selectedCard,
                matching: find.byType(Checkbox),
              ),
            )
            .value,
        isTrue,
      );

      final requestLines = fixture.requestLines;
      final pushesBeforeDialog = fixture.routes.pushed.length;
      final createButton = find.byKey(
        const ValueKey('admin_create_user_button'),
      );
      await tester.ensureVisible(createButton);
      await tester.tap(createButton);
      await tester.pumpAndSettle();
      final dialogRoute = fixture.routes.current;
      expect(find.byType(Dialog), findsOneWidget);
      final usernameField = _dialogTextFields(tester).first;
      await tester.enterText(usernameField, 'draft account 原文');
      final controller = tester.widget<TextField>(usernameField).controller!;
      controller.selection = const TextSelection(
        baseOffset: 1,
        extentOffset: 7,
      );
      final selection = controller.selection;
      final focusNode = tester
          .widget<EditableText>(
            find.descendant(
              of: usernameField,
              matching: find.byType(EditableText),
            ),
          )
          .focusNode;
      expect(FocusManager.instance.primaryFocus, same(focusNode));

      for (final locale in [AppLocale.en, AppLocale.zh]) {
        I18n.setLocale(locale);
        await tester.pumpAndSettle();
        expect(tester.element(module), same(moduleElement));
        expect(fixture.routes.current, same(dialogRoute));
        expect(fixture.routes.pushed, hasLength(pushesBeforeDialog + 1));
        expect(fixture.requestLines, requestLines);
        expect(controller.text, 'draft account 原文');
        expect(controller.selection, selection);
        expect(
          tester.widget<TextField>(_dialogTextFields(tester).first).controller,
          same(controller),
        );
        expect(FocusManager.instance.primaryFocus, same(focusNode));
        expect(find.text(_literalUsername), findsOneWidget);
        expect(scrollState.position.pixels, listOffset);
        expect(
          tester
              .widget<Checkbox>(
                find.descendant(
                  of: selectedCard,
                  matching: find.byType(Checkbox),
                ),
              )
              .value,
          isTrue,
        );
        expect(tester.takeException(), isNull);
        if (locale == AppLocale.en) {
          await _captureIfRequested(
            tester,
            fixture,
            'admin-users-390-en-create-draft',
          );
        }
      }

      fixture.navigatorKey.currentState!.pop(false);
      await tester.pumpAndSettle();
      expect(fixture.requestLines, requestLines);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Coin-only access reads users and sends one adjustment even when refresh fails',
    (tester) async {
      final fixture = await _mountUsers(tester, permissions: const ['coins']);
      expect(fixture.userReads, hasLength(1));
      expect(fixture.groupReads, hasLength(1));
      expect(fixture.roleReads, isEmpty);

      await _openUserAction(tester, _coinUserId, '调整时光币');
      final fields = _dialogTextFields(tester);
      await tester.enterText(fields[0], '42');
      await tester.enterText(fields[1], 'fixture adjustment reason');
      fixture.failNextUserReads = 1;
      await tester.ensureVisible(_dialogPrimaryButton());
      await tester.tap(_dialogPrimaryButton());
      await tester.pumpAndSettle();

      final coinWrites = fixture.userMutations
          .where((request) => request.path.endsWith('/$_coinUserId/coins'))
          .toList();
      expect(coinWrites, hasLength(1));
      expect(coinWrites.single.method, 'POST');
      expect(jsonDecode(coinWrites.single.body), {
        'delta': 42,
        'reason': 'fixture adjustment reason',
      });
      expect(fixture.userReads, hasLength(2));
      expect(fixture.groupReads, hasLength(1));
      expect(fixture.roleReads, isEmpty);
      final feedback = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(SnackBar),
              matching: find.byType(Text),
            ),
          )
          .map((text) => text.data ?? '')
          .join(' ');
      expect(feedback, contains('列表刷新失败'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Groups, roles, permissions, and none never read users before or after activation',
    (tester) async {
      final fixture = await _mountUsers(
        tester,
        initialTabIndex: 0,
        permissions: const ['groups'],
      );
      for (final permissions in [
        const ['roles'],
        const ['permissions'],
        const ['__none__'],
        const ['*', '__none__'],
        const ['__none__', '*'],
      ]) {
        fixture.auth.replaceState(permissions: permissions);
        await tester.pumpAndSettle();
        expect(fixture.userReads, isEmpty);
      }

      fixture.auth.replaceState(permissions: const ['coins']);
      await tester.pumpAndSettle();
      await _selectUsersTab(tester);
      expect(fixture.userReads, hasLength(1));
      expect(fixture.groupReads, hasLength(1));
      expect(fixture.roleReads, isEmpty);

      for (final permissions in [
        const ['groups'],
        const ['roles'],
        const ['permissions'],
        const ['__none__'],
        const ['*', '__none__'],
        const ['__none__', '*'],
      ]) {
        fixture.auth.replaceState(permissions: permissions);
        await tester.pumpAndSettle();
        expect(fixture.userReads, hasLength(1));
        expect(find.text(_literalUsername), findsNothing);
      }
      expect(fixture.groupReads, hasLength(1));
      expect(fixture.roleReads, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Retained search-clear callback cannot dispatch after permissions are revoked',
    (tester) async {
      final fixture = await _mountUsers(tester, permissions: const ['users']);
      await tester.enterText(_searchField(), 'alice 原文');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      final clearButton = find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == '清空搜索',
      );
      expect(clearButton, findsOneWidget);
      final staleClear = tester.widget<IconButton>(clearButton).onPressed!;
      final readsBeforeRevocation = fixture.userReads.length;

      fixture.auth.replaceState(permissions: const ['__none__']);
      await tester.pumpAndSettle();
      expect(() => staleClear(), returnsNormally);
      await tester.pumpAndSettle();
      expect(fixture.userReads, hasLength(readsBeforeRevocation));
      expect(find.text(_literalUsername), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Self account keeps password and permissions editors; cancelled and covered saves stay stale',
    (tester) async {
      final fixture = await _mountUsers(
        tester,
        permissions: const ['users', 'permissions'],
      );
      await tester.ensureVisible(_userCard(_selfId));
      final selfMenu = find.descendant(
        of: _userCard(_selfId),
        matching: find.byType(PopupMenuButton<String>),
      );
      await tester.tap(selfMenu);
      await tester.pumpAndSettle();
      expect(find.text('撤销管理员权限'), findsNothing);
      expect(find.text('禁用账号登录'), findsNothing);
      expect(find.text('删除账号与数据'), findsNothing);
      expect(find.text('重置登录密码'), findsOneWidget);
      expect(find.text('设置管理权限'), findsOneWidget);
      await tester.tap(find.text('重置登录密码'));
      await tester.pumpAndSettle();

      final firstField = _dialogTextFields(tester).single;
      final firstController = tester.widget<TextField>(firstField).controller!;
      await tester.enterText(firstField, 'stale password');
      final cancelledSave = _dialogPrimaryCallback(tester);
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();
      cancelledSave();
      await tester.pumpAndSettle();
      expect(fixture.userMutations, isEmpty);

      await _openUserAction(tester, _selfId, '重置登录密码');
      expect(_dialogTextFields(tester), hasLength(1));
      final reopenedController = tester
          .widget<TextField>(_dialogTextFields(tester).single)
          .controller!;
      expect(reopenedController, isNot(same(firstController)));
      expect(reopenedController.text, isEmpty);
      await tester.enterText(
        _dialogTextFields(tester).single,
        'new safe password',
      );
      final coveredSave = _dialogPrimaryCallback(tester);
      final dialogRoute = fixture.routes.current;
      final coverRoute = MaterialPageRoute<void>(
        builder: (_) =>
            const Scaffold(body: Center(child: Text('Cover route'))),
      );
      unawaited(fixture.navigatorKey.currentState!.push(coverRoute));
      await tester.pumpAndSettle();
      coveredSave();
      await tester.pumpAndSettle();
      expect(fixture.routes.current, same(coverRoute));
      expect(fixture.userMutations, isEmpty);

      fixture.navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(fixture.routes.current, same(dialogRoute));
      await tester.ensureVisible(_dialogPrimaryButton());
      await tester.tap(_dialogPrimaryButton());
      await tester.pumpAndSettle();
      final passwordWrites = fixture.userMutations
          .where((request) => request.path.endsWith('/$_selfId'))
          .toList();
      expect(passwordWrites, hasLength(1));
      expect(passwordWrites.single.method, 'PATCH');
      expect(jsonDecode(passwordWrites.single.body), {
        'new_password': 'new safe password',
      });

      await _openUserAction(tester, _selfId, '设置管理权限');
      expect(find.text('设置 literal self admin 原文 的管理权限'), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsWidgets);
      fixture.navigatorKey.currentState!.pop(false);
      await tester.pumpAndSettle();
      expect(fixture.userMutations, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Held user page is discarded after client replacement and same-frame tab return',
    (tester) async {
      final fixture = await _mountUsers(tester, permissions: const ['users']);
      final staleRefresh = _refreshCallback(tester);
      final held = fixture.holdNextUsersRead();
      staleRefresh();
      await tester.pump();
      await fixture.heldUserReadDispatched.future;

      fixture.replaceClient();
      await tester.pump();
      await tester.pumpAndSettle();
      final readCountAfterReplacement = fixture.userReads.length;
      expect(readCountAfterReplacement, greaterThan(2));
      staleRefresh();
      await tester.pumpAndSettle();
      expect(fixture.userReads, hasLength(readCountAfterReplacement));

      held.complete(
        _pageResponse(
          [_user('old-client-user', 'stale response 原文')],
          limit: 20,
          offset: 0,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('stale response 原文'), findsNothing);
      expect(find.text(_literalUsername), findsOneWidget);

      final currentRefresh = _refreshCallback(tester);
      final controller = tester
          .widget<TabBar>(find.byType(TabBar).first)
          .controller!;
      controller.index = 0;
      controller.index = 4;
      await tester.pumpAndSettle();
      final readsAfterAba = fixture.userReads.length;
      currentRefresh();
      await tester.pumpAndSettle();
      expect(fixture.userReads, hasLength(readsAfterAba));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Retained row action cannot reuse a silently changed client origin',
    (tester) async {
      final fixture = await _mountUsers(tester, permissions: const ['users']);
      final card = _userCard(_literalUserId);
      final menu = find.descendant(
        of: card,
        matching: find.byType(PopupMenuButton<String>),
      );
      final staleSelect = tester
          .widget<PopupMenuButton<String>>(menu)
          .onSelected!;

      fixture.auth.mutateClientSnapshot(
        baseUrl: 'https://admin-replacement.duoyi.test',
        token: 'replacement-same-client-token',
      );
      staleSelect('details');
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsNothing);
      expect(fixture.userReads, hasLength(2));
      expect(fixture.userReads.last.host, 'admin-replacement.duoyi.test');
      expect(
        fixture.userReads.last.authorization,
        'Bearer replacement-same-client-token',
      );
      expect(find.text(_literalUsername), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Open user details drops private fields after permission changes',
    (tester) async {
      final fixture = await _mountUsers(tester, permissions: const ['users']);
      await _openUserAction(tester, _literalUserId, '查看详情');
      final detail = find.byType(SelectableText);
      expect(detail, findsOneWidget);
      expect(
        tester.widget<SelectableText>(detail).data,
        contains(_literalUsername),
      );
      expect(
        tester.widget<SelectableText>(detail).data,
        contains('user-0@example.test'),
      );

      fixture.auth.replaceState(permissions: const ['__none__']);
      await tester.pumpAndSettle();
      expect(find.text('操作已失效'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text(_literalUsername),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text('user-0@example.test'),
        ),
        findsNothing,
      );
      expect(fixture.userMutations, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Auxiliary failures keep user rows visible in a narrow, enlarged keyboard layout',
    (tester) async {
      final fixture = await _mountUsers(
        tester,
        width: 320,
        height: 640,
        textScale: 1.6,
        permissions: const ['users', 'groups', 'roles'],
        failGroups: true,
        failRoles: true,
      );
      expect(fixture.userReads, hasLength(1));
      expect(fixture.groupReads, hasLength(1));
      expect(fixture.roleReads, hasLength(1));
      expect(find.text('用户组或角色加载失败'), findsOneWidget);
      await _captureIfRequested(
        tester,
        fixture,
        'admin-users-320-zh-large-text-main',
      );
      await tester.scrollUntilVisible(
        find.text(_literalUsername),
        320,
        scrollable: _userListScrollable(),
      );
      await tester.ensureVisible(find.text(_literalUsername));
      expect(find.text(_literalUsername), findsOneWidget);
      expect(
        find.byKey(const ValueKey('admin_users_toolbar_actions')),
        findsOneWidget,
      );

      await _openUserAction(tester, _selfId, '重置登录密码');
      final field = _dialogTextFields(tester).single;
      await tester.enterText(field, 'layout password');
      tester.view.viewInsets = const FakeViewPadding(bottom: 200);
      await tester.pumpAndSettle();
      await tester.ensureVisible(field);
      final visibleHeight = 640 - 200;
      for (final action in [_dialogCancelButton(), _dialogPrimaryButton()]) {
        expect(action.hitTestable(), findsOneWidget);
        expect(tester.getRect(action).bottom, lessThanOrEqualTo(visibleHeight));
      }
      expect(tester.takeException(), isNull);
      fixture.navigatorKey.currentState!.pop(false);
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
    },
  );
  for (final permissions in [
    const ['users'],
    const ['users', 'groups'],
    const ['users', 'roles'],
    const ['users', 'groups', 'roles'],
  ]) {
    testWidgets(
      'Create fields and payload require compound access $permissions',
      (tester) async {
        final fixture = await _mountUsers(tester, permissions: permissions);
        final create = find.byKey(const ValueKey('admin_create_user_button'));
        await tester.ensureVisible(create);
        await tester.pumpAndSettle();
        await tester.tap(create);
        await tester.pumpAndSettle();
        final dialog = find.byType(Dialog);
        final dropdowns = tester
            .widgetList<AppDropdownField<String>>(
              find.descendant(
                of: dialog,
                matching: find.byType(AppDropdownField<String>),
              ),
            )
            .toList();
        final groups = permissions.contains('groups');
        final roles = permissions.contains('roles');
        expect(dropdowns, hasLength((groups ? 1 : 0) + (roles ? 1 : 0)));
        if (roles) {
          expect(
            dropdowns.last.items.any((item) => item.value == 'role_admin'),
            isFalse,
          );
        }
        expect(find.text('管理员账号'), findsNothing);
        await tester.enterText(
          _dialogTextFields(tester).first,
          'synthetic-new-user',
        );
        await tester.ensureVisible(_dialogPrimaryButton());
        await tester.pumpAndSettle();
        await tester.tap(_dialogPrimaryButton());
        await tester.pumpAndSettle();
        final writes = fixture.requests
            .where((r) => r.method == 'POST' && r.path == '/api/admin/users')
            .toList();
        expect(writes, hasLength(1));
        final payload = jsonDecode(writes.single.body) as Map<String, dynamic>;
        expect(payload['username'], 'synthetic-new-user');
        expect(payload['is_admin'], isFalse);
        expect(payload.containsKey('group_id'), groups);
        expect(payload.containsKey('role_id'), roles);
        if (groups) expect(payload['group_id'], 'group_default');
        if (roles) expect(payload['role_id'], 'role_user');
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Explicit permissions editor can promote without standalone full access',
    (tester) async {
      final fixture = await _mountUsers(
        tester,
        permissions: const ['users', 'permissions'],
      );
      await _openUserAction(tester, _literalUserId, '设置管理权限');
      expect(find.text('授予管理员身份？'), findsOneWidget);
      await tester.tap(_dialogPrimaryButton());
      await tester.pumpAndSettle();
      final usersPermission = find.widgetWithText(CheckboxListTile, '用户');
      await tester.ensureVisible(usersPermission);
      await tester.pumpAndSettle();
      await tester.tap(usersPermission);
      await tester.pumpAndSettle();
      await tester.ensureVisible(_dialogPrimaryButton());
      await tester.pumpAndSettle();
      await tester.tap(_dialogPrimaryButton());
      await tester.pumpAndSettle();
      final writes = fixture.userMutations;
      expect(writes, hasLength(1));
      expect(writes.single.method, 'PATCH');
      expect(writes.single.path, '/api/admin/users/$_literalUserId');
      expect(jsonDecode(writes.single.body), {
        'is_admin': true,
        'role_id': 'role_user',
        'admin_permissions': ['users'],
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Late coin response cannot refresh or release a newer dialog', (
    tester,
  ) async {
    final fixture = await _mountUsers(tester, permissions: const ['coins']);
    await _openUserAction(tester, _literalUserId, '调整时光币');
    await tester.enterText(_dialogTextFields(tester).first, '7');
    final held = fixture.holdRequest(
      'POST',
      '/api/admin/users/$_literalUserId/coins',
    );
    await tester.tap(_dialogPrimaryButton());
    await tester.pumpAndSettle();
    await held.$1.future;
    fixture.replaceClient();
    await tester.pumpAndSettle();
    final reads = fixture.userReads.length;
    await _openUserAction(tester, _literalUserId, '调整时光币');
    await tester.enterText(_dialogTextFields(tester).first, '4');
    final controller = tester
        .widget<TextField>(_dialogTextFields(tester).first)
        .controller!;
    held.$2.complete(
      _jsonResponse({'balance': 999, 'lifetime': 999, 'server_version': 1}),
    );
    await tester.pumpAndSettle();
    expect(fixture.userReads, hasLength(reads));
    expect(find.byType(Dialog), findsOneWidget);
    expect(controller.text, '4');
    expect(fixture.userMutations, hasLength(1));
    expect(find.byType(SnackBar), findsNothing);
    await tester.tap(_dialogPrimaryButton());
    await tester.pumpAndSettle();
    final writes = fixture.userMutations
        .where((r) => r.path.endsWith('/coins'))
        .toList();
    expect(writes, hasLength(2));
    expect(jsonDecode(writes.last.body), {'delta': 4});
    expect(fixture.userReads, hasLength(reads + 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Expired held CSV cannot diagnose routes or disturb a newer operation',
    (tester) async {
      final fixture = await _mountUsers(tester, permissions: const ['users']);
      final held = fixture.holdRequest('GET', '/api/admin/users/export.csv');
      final export = find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == '导出用户筛选结果',
      );
      await tester.ensureVisible(export);
      await tester.pumpAndSettle();
      await tester.tap(export);
      await tester.pumpAndSettle();
      await held.$1.future;
      fixture.replaceClient();
      await tester.pumpAndSettle();
      await _openUserAction(tester, _selfId, '重置登录密码');
      await tester.enterText(
        _dialogTextFields(tester).single,
        'retained new draft',
      );
      final reads = fixture.userReads.length;
      held.$2.complete(
        _jsonResponse({'detail': 'expired export'}, status: 404),
      );
      await tester.pumpAndSettle();
      expect(fixture.userReads, hasLength(reads));
      expect(fixture.requests.where((r) => r.path == '/api/config'), isEmpty);
      expect(
        fixture.requests.where((r) => r.path == '/api/admin/users/export.csv'),
        hasLength(1),
      );
      expect(find.byType(Dialog), findsOneWidget);
      expect(
        tester
            .widget<TextField>(_dialogTextFields(tester).single)
            .controller!
            .text,
        'retained new draft',
      );
      expect(find.byType(SnackBar), findsNothing);
      fixture.navigatorKey.currentState!.pop(false);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Users timer skips owned dialogs, covering routes, and inactive tabs',
    (tester) async {
      final fixture = await _mountUsers(tester, permissions: const ['users']);
      var reads = fixture.userReads.length;
      await tester.pump(const Duration(seconds: 61));
      await tester.pumpAndSettle();
      expect(fixture.userReads, hasLength(++reads));

      await _openUserAction(tester, _literalUserId, '查看详情');
      await tester.pump(const Duration(seconds: 61));
      await tester.pumpAndSettle();
      expect(fixture.userReads, hasLength(reads));
      fixture.navigatorKey.currentState!.pop(false);
      await tester.pumpAndSettle();
      reads = fixture.userReads.length;

      final cover = MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Timer cover')),
      );
      unawaited(fixture.navigatorKey.currentState!.push(cover));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 61));
      await tester.pumpAndSettle();
      expect(fixture.userReads, hasLength(reads));
      fixture.navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      reads = fixture.userReads.length;
      await tester.pump(const Duration(seconds: 61));
      await tester.pumpAndSettle();
      expect(fixture.userReads, hasLength(++reads));

      final tabs = tester.widget<TabBar>(find.byType(TabBar).first).controller!;
      tabs.index = 0;
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 61));
      await tester.pumpAndSettle();
      expect(fixture.userReads, hasLength(reads));
      await _selectUsersTab(tester);
      reads = fixture.userReads.length;
      await tester.pump(const Duration(seconds: 61));
      await tester.pumpAndSettle();
      expect(fixture.userReads, hasLength(reads + 1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Failed Users retry freezes submitted parameters and rejects newer reads',
    (tester) async {
      final fixture = await _mountUsers(tester, permissions: const ['users']);
      await tester.enterText(_searchField(), 'submitted query 原文');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      final status = find.widgetWithText(ChoiceChip, '已禁用');
      await tester.ensureVisible(status);
      await tester.tap(status);
      await tester.pumpAndSettle();
      tester
          .widget<AppCompactDropdown<String>>(
            find.byType(AppCompactDropdown<String>),
          )
          .onChanged!('username_asc');
      await tester.pumpAndSettle();
      fixture.failNextUserReads = 1;
      _refreshCallback(tester)();
      await tester.pumpAndSettle();
      final failedParameters = Map<String, String>.of(
        fixture.userReads.last.queryParameters,
      );
      final retryButton = find.descendant(
        of: _usersModule(),
        matching: find.widgetWithIcon(OutlinedButton, Icons.refresh),
      );
      expect(retryButton, findsOneWidget);
      final retry = tester.widget<OutlinedButton>(retryButton).onPressed!;
      await tester.enterText(_searchField(), 'unsent newer draft');
      retry();
      await tester.pumpAndSettle();
      expect(fixture.userReads.last.queryParameters, failedParameters);

      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(fixture.userReads.last.queryParameters['q'], 'unsent newer draft');
      final reads = fixture.userReads.length;
      retry();
      await tester.pumpAndSettle();
      expect(fixture.userReads, hasLength(reads));
      expect(tester.takeException(), isNull);
    },
  );
}

Future<_UsersFixture> _mountUsers(
  WidgetTester tester, {
  int initialTabIndex = 4,
  List<String> permissions = const ['users'],
  double width = 390,
  double height = 900,
  double textScale = 1,
  bool failGroups = false,
  bool failRoles = false,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final fixture = _UsersFixture(
    permissions: permissions,
    failGroups: failGroups,
    failRoles: failRoles,
  );
  await tester.runAsync(loadWidgetPolishScreenshotFonts);
  final fonts = widgetPolishScreenshotTheme();
  await tester.pumpWidget(
    MultiProvider(
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
        home: AdminScreen(initialTabIndex: initialTabIndex),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });
  return fixture;
}

Finder _usersModule() => find.byKey(const ValueKey('admin-users-0'));

Future<void> _captureIfRequested(
  WidgetTester tester,
  _UsersFixture fixture,
  String name,
) async {
  final directoryPath =
      Platform.environment['DUOYI_ADMIN_USERS_SCREENSHOT_DIR'];
  if (directoryPath == null || directoryPath.trim().isEmpty) return;
  final requiredRoot = Directory(
    'evidence/screenshots/admin-users-v355',
  ).absolute.path;
  final outputDirectory = Directory(directoryPath).absolute.path;
  if (outputDirectory != requiredRoot &&
      !outputDirectory.startsWith('$requiredRoot${Platform.pathSeparator}')) {
    throw StateError(
      'DUOYI_ADMIN_USERS_SCREENSHOT_DIR must stay under evidence/screenshots/admin-users-v355/.',
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

Finder _userCard(String userId) =>
    find.byKey(ValueKey('admin_user_mobile_card_$userId'));

Finder _userListScrollable() {
  final list = find.descendant(
    of: _usersModule(),
    matching: find.byType(ListView),
  );
  return find
      .descendant(of: list.first, matching: find.byType(Scrollable))
      .first;
}

Finder _searchField() => find.byWidgetPredicate(
  (widget) =>
      widget is TextField &&
      (widget.decoration?.hintText?.contains('搜索用户名') == true ||
          widget.decoration?.hintText?.contains('Search username') == true),
);

List<Finder> _dialogTextFields(WidgetTester tester) {
  final dialog = find.byType(Dialog);
  expect(dialog, findsOneWidget);
  return find
      .descendant(of: dialog, matching: find.byType(TextField))
      .evaluate()
      .map(
        (element) => find.byElementPredicate(
          (candidate) => identical(candidate, element),
        ),
      )
      .toList();
}

Finder _dialogPrimaryButton() => find
    .descendant(of: find.byType(Dialog), matching: find.byType(FilledButton))
    .last;

VoidCallback _dialogPrimaryCallback(WidgetTester tester) =>
    tester.widget<FilledButton>(_dialogPrimaryButton()).onPressed!;

Finder _dialogCancelButton() => find.descendant(
  of: find.byType(Dialog),
  matching: find.widgetWithText(TextButton, '取消'),
);

Finder _refreshButton() => find.descendant(
  of: _usersModule(),
  matching: find.widgetWithIcon(IconButton, Icons.refresh),
);

VoidCallback _refreshCallback(WidgetTester tester) =>
    tester.widget<IconButton>(_refreshButton()).onPressed!;

Future<void> _selectUsersTab(WidgetTester tester) async {
  final tabBar = tester.widget<TabBar>(find.byType(TabBar).first);
  tabBar.controller!.animateTo(4, duration: Duration.zero);
  await tester.pumpAndSettle();
}

Future<void> _openUserAction(
  WidgetTester tester,
  String userId,
  String actionLabel,
) async {
  final card = _userCard(userId);
  await tester.scrollUntilVisible(card, 320, scrollable: _userListScrollable());
  final menu = find.descendant(
    of: card,
    matching: find.byType(PopupMenuButton<String>),
  );
  expect(menu, findsOneWidget);
  await tester.ensureVisible(menu);
  await tester.pumpAndSettle();
  expect(menu.hitTestable(), findsOneWidget);
  await tester.tap(menu);
  await tester.pumpAndSettle();
  expect(find.text(actionLabel), findsOneWidget);
  await tester.tap(find.text(actionLabel));
  await tester.pumpAndSettle();
  expect(find.byType(Dialog), findsOneWidget);
}

AuthState _adminState({
  required List<String> permissions,
  String userId = _selfId,
  String token = 'synthetic-admin-token',
}) => AuthState(
  userId: userId,
  username: 'literal-admin',
  token: token,
  isAdmin: true,
  adminPermissions: permissions,
);

Map<String, dynamic> _user(String id, String username, {bool self = false}) => {
  'user_id': id,
  'username': username,
  'display_name': self ? 'literal display 原文' : 'Literal display $id',
  'email': self ? 'self@example.test' : '$id@example.test',
  'email_verified': true,
  'is_admin': self,
  'is_disabled': false,
  'online': false,
  'admin_permissions': self ? const ['*'] : const <String>[],
  'group_id': 'group_default',
  'role_id': self ? 'role_admin' : 'role_user',
  'coin_balance': 100,
  'lifetime_coins': 900,
  'feedback_count': 0,
  'created_at': '2026-10-01 08:00:00',
  'last_login_at': null,
  'last_active_at': null,
};

List<Map<String, dynamic>> _initialUsers() => [
  _user(_selfId, 'literal self admin 原文', self: true),
  for (var index = 0; index < 18; index++)
    _user(
      'user-$index',
      index == 0 ? _literalUsername : 'literal-user-$index 原文',
    ),
];

http.Response _pageResponse(
  List<Map<String, dynamic>> users, {
  required int limit,
  required int offset,
}) {
  final items = users.skip(offset).take(limit).toList();
  return _jsonResponse({
    'items': items,
    'total': users.length,
    'limit': limit,
    'offset': offset,
    'has_more': offset + items.length < users.length,
  });
}

http.Response _jsonResponse(Object body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);

class _UsersFixture {
  _UsersFixture({
    required List<String> permissions,
    required this.failGroups,
    required this.failRoles,
  }) {
    auth = _SwitchableAuth(
      client: newClient(token: 'synthetic-admin-token'),
      state: _adminState(permissions: permissions),
    );
  }

  final bool failGroups;
  final bool failRoles;
  final List<_CapturedRequest> requests = [];
  final List<http.Client> transports = [];
  final ThemeProvider theme = ThemeProvider();
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();
  final GlobalKey screenshotKey = GlobalKey();
  final _RecordingNavigatorObserver routes = _RecordingNavigatorObserver();
  final List<Map<String, dynamic>> users = _initialUsers();
  late final _SwitchableAuth auth;
  int failNextUserReads = 0;
  Completer<http.Response>? _nextUserRead;
  Completer<void>? _heldUserReadDispatched;

  final Map<String, (Completer<void>, Completer<http.Response>)> _heldRequests =
      {};

  (Completer<void>, Completer<http.Response>) holdRequest(
    String method,
    String path,
  ) {
    final held = (Completer<void>(), Completer<http.Response>());
    _heldRequests['$method $path'] = held;
    return held;
  }

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

  List<_CapturedRequest> get userReads => requests
      .where(
        (request) =>
            request.method == 'GET' && request.path == '/api/admin/users',
      )
      .toList();

  List<_CapturedRequest> get groupReads => requests
      .where(
        (request) =>
            request.method == 'GET' && request.path == '/api/admin/groups',
      )
      .toList();

  List<_CapturedRequest> get roleReads => requests
      .where(
        (request) =>
            request.method == 'GET' && request.path == '/api/admin/roles',
      )
      .toList();

  List<_CapturedRequest> get userMutations => requests
      .where(
        (request) =>
            request.path.startsWith('/api/admin/users/') &&
            request.method != 'GET',
      )
      .toList();

  List<String> get requestLines =>
      requests.map((request) => request.line).toList();

  Completer<http.Response> holdNextUsersRead() {
    final response = Completer<http.Response>();
    _nextUserRead = response;
    _heldUserReadDispatched = Completer<void>();
    return response;
  }

  Completer<void> get heldUserReadDispatched => _heldUserReadDispatched!;

  void replaceClient() {
    auth.replaceClient(newClient(token: auth.state.token!));
  }

  Future<http.Response> _handle(http.Request request) async {
    final captured = _CapturedRequest(
      method: request.method,
      path: request.url.path,
      query: request.url.query,
      body: request.body,
      host: request.url.host,
      authorization: request.headers['authorization'] ?? '',
      queryParameters: Map<String, String>.of(request.url.queryParameters),
    );
    requests.add(captured);
    final heldRequest = _heldRequests.remove(
      '${request.method} ${request.url.path}',
    );
    if (heldRequest != null) {
      heldRequest.$1.complete();
      return heldRequest.$2.future;
    }

    if (request.method == 'GET' && request.url.path == '/api/admin/users') {
      final held = _nextUserRead;
      _nextUserRead = null;
      if (held != null) {
        if (!_heldUserReadDispatched!.isCompleted) {
          _heldUserReadDispatched!.complete();
        }
        return held.future;
      }
      if (failNextUserReads > 0) {
        failNextUserReads--;
        return _jsonResponse({
          'detail': 'fixture refresh failure',
        }, status: 500);
      }
      final limit =
          int.tryParse(request.url.queryParameters['limit'] ?? '') ?? 20;
      final offset =
          int.tryParse(request.url.queryParameters['offset'] ?? '') ?? 0;
      return _pageResponse(users, limit: limit, offset: offset);
    }

    if (request.method == 'GET' && request.url.path == '/api/admin/groups') {
      if (failGroups) {
        return _jsonResponse({'detail': 'groups unavailable'}, status: 500);
      }
      return _jsonResponse({
        'items': [
          {
            'id': 'group_default',
            'name': 'Literal default group',
            'is_active': true,
            'user_count': users.length,
          },
        ],
      });
    }
    if (request.method == 'GET' && request.url.path == '/api/admin/roles') {
      if (failRoles) {
        return _jsonResponse({'detail': 'roles unavailable'}, status: 500);
      }
      return _jsonResponse([
        {
          'id': 'role_user',
          'name': 'Literal user role',
          'is_active': true,
          'user_count': users.length,
        },
        {
          'id': 'role_admin',
          'name': 'Literal admin role',
          'is_active': true,
          'user_count': 1,
        },
      ]);
    }

    if (request.method != 'GET' &&
        request.url.path.startsWith('/api/admin/users/')) {
      if (request.url.path.endsWith('/coins')) {
        return _jsonResponse({
          'balance': 142,
          'lifetime': 942,
          'server_version': 1,
        });
      }
      return _jsonResponse(<String, Object>{});
    }
    if (request.method == 'POST' && request.url.path == '/api/admin/users') {
      return _jsonResponse({'user_id': 'created-user'});
    }

    if (request.method == 'GET') {
      if (request.url.path == '/api/admin/stats') {
        return _jsonResponse({
          'users': {'total': users.length, 'disabled': 0},
          'feedback': {'total': 0, 'open': 0},
          'announcements': {'total': 0, 'published': 0},
          'invites': {'total': 0, 'used': 0},
          'registration_series': <Object>[],
        });
      }
      final limit =
          int.tryParse(request.url.queryParameters['limit'] ?? '') ?? 20;
      final offset =
          int.tryParse(request.url.queryParameters['offset'] ?? '') ?? 0;
      return _jsonResponse({
        'items': <Object>[],
        'total': 0,
        'limit': limit,
        'offset': offset,
        'has_more': false,
      });
    }
    return _jsonResponse(<String, Object>{});
  }

  void dispose() {
    auth.dispose();
    for (final transport in transports) {
      transport.close();
    }
    theme.dispose();
  }
}

class _SwitchableAuth extends AuthProvider {
  _SwitchableAuth({required ApiClient client, required AuthState state})
    : _currentClient = client,
      _currentState = state,
      super(client: client, initialState: state);

  ApiClient _currentClient;
  AuthState _currentState;

  @override
  ApiClient get client => _currentClient;

  @override
  AuthState get state => _currentState;

  void replaceClient(ApiClient client) {
    _currentClient = client;
    notifyListeners();
  }

  void replaceState({required List<String> permissions}) {
    _currentState = _adminState(permissions: permissions);
    notifyListeners();
  }

  void mutateClientSnapshot({String? baseUrl, String? token}) {
    if (baseUrl != null) _currentClient.baseUrl = baseUrl;
    if (token != null) {
      _currentClient.token = token;
      _currentState = _currentState.copyWith(token: token);
    }
  }
}

class _CapturedRequest {
  const _CapturedRequest({
    required this.method,
    required this.path,
    required this.query,
    required this.body,
    required this.host,
    required this.authorization,
    required this.queryParameters,
  });

  final String method;
  final String path;
  final String query;
  final String body;
  final String host;
  final String authorization;
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
}
