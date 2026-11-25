import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/admin_audit_ui_copy.dart';
import 'package:duoyi/core/admin_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/screens/admin_screen.dart';
import 'package:duoyi/services/app_access_route_gate.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import '../support/widget_polish_screenshot_font.dart';

const _selfId = 'audit-admin';
const _auditPath = '/api/admin/audit-log';

void main() {
  setUp(() => I18n.setLocale(AppLocale.zh));
  tearDown(() => I18n.setLocale(AppLocale.zh));

  testWidgets(
    'Audit locale changes preserve literal rows, query, filter, page, draft, focus, scroll, and requests',
    (tester) async {
      final fixture = await _mountAudit(tester);
      expect(fixture.auditReads, hasLength(1));
      expect(find.text('审计日志'), findsOneWidget);
      expect(
        tester.widget<TextField>(_searchField()).decoration!.hintText,
        '搜索管理员、操作、对象或详情',
      );
      expect(find.widgetWithText(ChoiceChip, '回复反馈'), findsOneWidget);
      expect(find.text('日志排序'), findsOneWidget);
      _expectLiteralAuditRow(tester, AppLocale.zh, 43, unknownAction: true);

      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      expect(find.text('Audit log'), findsOneWidget);
      expect(
        tester.widget<TextField>(_searchField()).decoration!.hintText,
        'Search administrators, actions, targets or details',
      );
      expect(
        find.widgetWithText(ChoiceChip, 'Reply to feedback'),
        findsOneWidget,
      );
      expect(find.text('Sort audit log'), findsOneWidget);
      _expectLiteralAuditRow(tester, AppLocale.en, 43, unknownAction: true);
      expect(fixture.auditReads, hasLength(1));

      I18n.setLocale(AppLocale.zh);
      await tester.pumpAndSettle();

      await tester.enterText(_searchField(), 'literal');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      final replyChip = find.byKey(
        const ValueKey('admin_audit_action_feedback.reply'),
      );
      await tester.ensureVisible(replyChip);
      await _tapHitTestableWidget(
        tester,
        replyChip,
        (widget) => widget is ChoiceChip && widget.onSelected != null,
      );
      final sortKeyFinder = _sortControl();
      expect(sortKeyFinder, findsOneWidget);
      final sortKey = sortKeyFinder.evaluate().single.widget.key;
      final readsBeforeSortPicker = fixture.auditReads.length;
      await _tapHitTestableWidget(
        tester,
        sortKeyFinder,
        (widget) => widget is InkWell && widget.onTap != null,
      );
      expect(find.text('管理员 A-Z'), findsOneWidget);
      expect(find.byKey(const ValueKey('admin_audit_picker')), findsOneWidget);
      await _tapEnabledButton(tester, find.widgetWithText(TextButton, '取消'));
      expect(fixture.auditReads, hasLength(readsBeforeSortPicker));
      expect(sortKeyFinder, findsOneWidget);

      await _tapHitTestableWidget(
        tester,
        sortKeyFinder,
        (widget) => widget is InkWell && widget.onTap != null,
      );
      final zhSortOption = find.text('管理员 A-Z').last;
      final zhSortOptionTile = find.ancestor(
        of: zhSortOption,
        matching: find.byType(ListTile),
      );
      await _tapHitTestableWidget(
        tester,
        zhSortOptionTile,
        (widget) => widget is ListTile && widget.onTap != null,
      );
      expect(fixture.auditReads, hasLength(readsBeforeSortPicker + 1));
      expect(fixture.auditReads.last.queryParameters, {
        'action': 'feedback.reply',
        'q': 'literal',
        'sort': 'actor_asc',
        'limit': '20',
        'offset': '0',
      });
      await _scrollAuditUntilHitTestable(tester, _nextPageButton());
      await _tapEnabledButton(tester, _nextPageButton());
      expect(fixture.auditReads, hasLength(readsBeforeSortPicker + 2));

      expect(fixture.auditReads.last.queryParameters, {
        'action': 'feedback.reply',
        'q': 'literal',
        'sort': 'actor_asc',
        'limit': '20',
        'offset': '20',
      });
      await _returnToAuditTop(tester);
      expect(tester.widget<ChoiceChip>(replyChip).selected, isTrue);
      final field = tester.widget<TextField>(_searchField());
      final controller = field.controller!;
      await tester.enterText(_searchField(), 'unsent draft 原文');
      controller.selection = const TextSelection(
        baseOffset: 2,
        extentOffset: 8,
      );
      final selection = controller.selection;
      final focusNode = tester
          .widget<EditableText>(
            find.descendant(
              of: _searchField(),
              matching: find.byType(EditableText),
            ),
          )
          .focusNode;
      expect(FocusManager.instance.primaryFocus, same(focusNode));

      final scrollable = _auditBodyScrollable();
      final scrollState = tester.state<ScrollableState>(scrollable);
      final maxScroll = scrollState.position.maxScrollExtent;
      if (maxScroll > 0) {
        scrollState.position.jumpTo(maxScroll.clamp(0.0, 64.0).toDouble());
        await tester.pumpAndSettle();
      }
      final scrollOffset = scrollState.position.pixels;
      expect(scrollOffset, greaterThan(0));
      final moduleElement = tester.element(_auditModule());
      final requestLines = List<String>.of(fixture.requestLines);

      for (final locale in [AppLocale.en, AppLocale.zh]) {
        I18n.setLocale(locale);
        await tester.pumpAndSettle();
        expect(_searchField(), findsOneWidget);
        expect(_sortControl(), findsOneWidget);
        expect(_sortControl().hitTestable(), findsOneWidget);
        expect(tester.element(_auditModule()), same(moduleElement));
        expect(fixture.requestLines, requestLines);
        expect(controller.text, 'unsent draft 原文');
        expect(controller.selection, selection);
        expect(
          tester.widget<TextField>(_searchField()).controller,
          same(controller),
        );
        expect(FocusManager.instance.primaryFocus, same(focusNode));
        expect(scrollState.position.pixels, closeTo(scrollOffset, 0.01));
        expect(
          tester.widget<IconButton>(_clearSearchButton()).tooltip,
          locale == AppLocale.zh ? '清空日志搜索' : 'Clear audit search',
        );
        expect(tester.widget<InkWell>(_sortControl()).key, equals(sortKey));
        expect(
          find.widgetWithText(
            ChoiceChip,
            locale == AppLocale.zh ? '回复反馈' : 'Reply to feedback',
          ),
          findsOneWidget,
        );
        expect(
          find.text(locale == AppLocale.zh ? '管理员 A-Z' : 'Administrator A–Z'),
          findsOneWidget,
        );
        expect(fixture.auditReads.last.queryParameters, {
          'action': 'feedback.reply',
          'q': 'literal',
          'sort': 'actor_asc',
          'limit': '20',
          'offset': '20',
        });
        expect(tester.takeException(), isNull);
        if (locale == AppLocale.en) {
          await _captureIfRequested(
            tester,
            fixture,
            'audit-390-en-filtered-draft',
          );
        }
      }

      for (final locale in [AppLocale.en, AppLocale.zh]) {
        I18n.setLocale(locale);
        await tester.pumpAndSettle();
        expect(scrollState.position.pixels, closeTo(scrollOffset, 0.01));
        expect(sortKeyFinder, findsOneWidget);
        final readsBeforePicker = fixture.auditReads.length;
        await _tapHitTestableWidget(
          tester,
          sortKeyFinder,
          (widget) => widget is InkWell && widget.onTap != null,
        );
        final pickerOption = find.descendant(
          of: find.byKey(const ValueKey('admin_audit_picker')),
          matching: find.text(
            locale == AppLocale.zh ? '管理员 A-Z' : 'Administrator A–Z',
          ),
        );
        expect(pickerOption, findsOneWidget);
        expect(
          find.byKey(const ValueKey('admin_audit_picker')),
          findsOneWidget,
        );
        await _captureIfRequested(
          tester,
          fixture,
          locale == AppLocale.zh
              ? 'audit-390-zh-sort-picker'
              : 'audit-390-en-sort-picker',
        );
        await _tapEnabledButton(
          tester,
          find.widgetWithText(
            TextButton,
            locale == AppLocale.zh ? '取消' : 'Cancel',
          ),
        );
        expect(fixture.auditReads, hasLength(readsBeforePicker));
        expect(scrollState.position.pixels, closeTo(scrollOffset, 0.01));
      }
    },
  );

  testWidgets(
    'Audit access requires audit permission and honors explicit none',
    (tester) async {
      for (final permissions in [
        const ['audit'],
        const ['feedback'],
        const ['__none__'],
        const ['*', '__none__'],
      ]) {
        final fixture = await _mountAudit(tester, permissions: permissions);
        if (permissions.contains('audit') &&
            !permissions.contains('__none__')) {
          expect(fixture.auditReads, hasLength(1), reason: '$permissions');
        } else {
          expect(fixture.auditReads, isEmpty, reason: '$permissions');
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets('Empty and no-match Audit copy follows locale without refetching', (
    tester,
  ) async {
    final fixture = await _mountAudit(tester);
    fixture.logs = [];
    await _tapEnabledButton(tester, _refreshButton());
    expect(fixture.auditReads, hasLength(2));
    expect(find.text('暂无操作记录'), findsOneWidget);

    I18n.setLocale(AppLocale.en);
    await tester.pumpAndSettle();
    expect(find.text('No activity recorded yet.'), findsOneWidget);
    expect(fixture.auditReads, hasLength(2));
    await _captureIfRequested(tester, fixture, 'audit-390-en-empty');

    await tester.ensureVisible(_searchField());
    await tester.enterText(_searchField(), 'literal');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(fixture.auditReads, hasLength(3));
    expect(
      find.text('No matching activity. Adjust your filters.'),
      findsOneWidget,
    );
    I18n.setLocale(AppLocale.zh);
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的操作记录，请调整筛选条件'), findsOneWidget);
    expect(fixture.auditReads, hasLength(3));
    await _captureIfRequested(tester, fixture, 'audit-390-zh-no-matches');

    fixture.failNextAuditReads = 1;
    await _returnToAuditTop(tester, target: _refreshButton());
    await _tapEnabledButton(tester, _refreshButton());
    expect(fixture.auditReads, hasLength(4));
    const zhError = '无法加载审计日志：服务暂不可用，请稍后重试或联系管理员';
    const enError =
        'Could not load Audit log: Service unavailable. Please try again later or contact an administrator.';
    const syntheticServerError = ApiException('500: literal audit failure');
    expect(
      AdminUiCopy.formatLoadError(
        syntheticServerError,
        AdminAuditUiCopy.titleFor(AppLocale.zh),
        locale: AppLocale.zh,
      ),
      zhError,
    );
    expect(
      AdminUiCopy.formatLoadError(
        syntheticServerError,
        AdminAuditUiCopy.titleFor(AppLocale.en),
        locale: AppLocale.en,
      ),
      enError,
    );
    await _scrollAuditUntilHitTestable(tester, find.text(zhError));
    expect(find.text(zhError), findsOneWidget);
    await _captureIfRequested(tester, fixture, 'audit-390-zh-error');
    I18n.setLocale(AppLocale.en);
    await tester.pumpAndSettle();
    expect(fixture.auditReads, hasLength(4));
    await _scrollAuditUntilHitTestable(tester, find.text(enError));
    expect(find.text(enError), findsOneWidget);
    await _captureIfRequested(tester, fixture, 'audit-390-en-error');
  });

  testWidgets(
    'Retained Audit callbacks expire across permission revoke and regrant ABA',
    (tester) async {
      final fixture = await _mountAudit(tester);
      await tester.enterText(_searchField(), 'literal');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      final staleSubmit = tester.widget<TextField>(_searchField()).onSubmitted!;
      final clearFinder = _clearSearchButton();
      expect(clearFinder, findsOneWidget);
      final staleClear = tester.widget<IconButton>(clearFinder).onPressed!;
      final chipFinder = find.byKey(
        const ValueKey('admin_audit_action_feedback.reply'),
      );
      final staleChip = tester.widget<ChoiceChip>(chipFinder).onSelected!;
      final staleRefresh = tester
          .widget<TextButton>(_refreshButton())
          .onPressed!;
      final staleSortOpen = tester.widget<InkWell>(_sortControl()).onTap!;
      await _scrollAuditUntilHitTestable(tester, _nextPageButton());
      final nextPageWidget = tester.widget<IconButton>(_nextPageButton());
      expect(nextPageWidget.onPressed, isNotNull);
      final staleNextPage = nextPageWidget.onPressed!;

      fixture.failNextAuditReads = 1;
      await _returnToAuditTop(tester, target: _refreshButton());
      await _tapEnabledButton(tester, _refreshButton());
      const errorMessage = '无法加载审计日志：服务暂不可用，请稍后重试或联系管理员';
      expect(find.text(errorMessage), findsOneWidget);
      final retryFinder = find.descendant(
        of: _auditModule(),
        matching: find.widgetWithIcon(OutlinedButton, Icons.refresh),
      );
      await _scrollAuditUntilHitTestable(tester, retryFinder);
      final retryButton = tester.widget<OutlinedButton>(retryFinder);
      expect(retryButton.onPressed, isNotNull);
      final staleRetry = retryButton.onPressed!;

      fixture.auth.replacePermissions(const ['__none__']);
      fixture.auth.replacePermissions(const ['audit']);
      await tester.pumpAndSettle();
      final readsAfterRegrant = fixture.auditReads.length;

      staleSubmit('stale query');
      staleClear();
      staleChip(false);
      staleRefresh();
      staleRetry();
      staleNextPage();
      staleSortOpen();
      await tester.pumpAndSettle();

      expect(fixture.auditReads, hasLength(readsAfterRegrant));
      expect(find.byKey(const ValueKey('admin_audit_picker')), findsNothing);
      expect(
        fixture.requests.where((request) => request.path == '/api/config'),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Audit same-frame tab ABA expires callbacks and held rows', (
    tester,
  ) async {
    final fixture = await _mountAudit(tester);
    final staleSubmit = tester.widget<TextField>(_searchField()).onSubmitted!;
    final staleChip = tester
        .widget<ChoiceChip>(
          find.byKey(const ValueKey('admin_audit_action_feedback.reply')),
        )
        .onSelected!;
    final held = fixture.holdNextAuditRead();
    await _tapEnabledButton(tester, _refreshButton(), settleAfterTap: false);
    await tester.pump();
    await held.$1.future;
    await tester.pump();
    expect(find.text('正在更新审计日志'), findsOneWidget);
    final readsWhileUpdating = fixture.auditReads.length;
    I18n.setLocale(AppLocale.en);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Updating audit log'), findsOneWidget);
    expect(fixture.auditReads, hasLength(readsWhileUpdating));
    I18n.setLocale(AppLocale.zh);
    await tester.pump(const Duration(milliseconds: 200));

    final tabs = tester.widget<TabBar>(find.byType(TabBar).first).controller!;
    tabs.index = 8;
    tabs.index = 9;
    await tester.pumpAndSettle();
    final requestsAfterReturn = fixture.auditReads.length;
    expect(requestsAfterReturn, 3);

    staleSubmit('old rendered search');
    staleChip(true);
    await tester.pumpAndSettle();
    expect(fixture.auditReads, hasLength(requestsAfterReturn));
    held.$2.complete(
      _json({
        'items': [_auditItem(90, action: 'stale.aba.action')],
        'total': 1,
        'limit': 20,
        'offset': 0,
      }),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('stale.aba.action'), findsNothing);
    expect(fixture.auditReads, hasLength(requestsAfterReturn));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Audit normal leave and return starts a fresh authorized read', (
    tester,
  ) async {
    final fixture = await _mountAudit(tester);
    expect(fixture.auditReads, hasLength(1));
    expect(find.textContaining('literal actor 原文 44'), findsOneWidget);

    final tabs = tester.widget<TabBar>(find.byType(TabBar).first).controller!;
    tabs.index = 8;
    await tester.pumpAndSettle();
    expect(fixture.auditReads, hasLength(1));

    tabs.index = 9;
    await tester.pumpAndSettle();
    expect(fixture.auditReads, hasLength(2));
    expect(fixture.auditReads.last.queryParameters, {
      'sort': 'created_desc',
      'limit': '20',
      'offset': '0',
    });
    expect(find.textContaining('literal actor 原文 44'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Same-frame route ABA expires Audit callbacks and held rows', (
    tester,
  ) async {
    final fixture = await _mountAudit(tester);
    final staleSubmit = tester.widget<TextField>(_searchField()).onSubmitted!;
    final staleChip = tester
        .widget<ChoiceChip>(
          find.byKey(const ValueKey('admin_audit_action_feedback.reply')),
        )
        .onSelected!;
    final held = fixture.holdNextAuditRead();
    await _tapEnabledButton(tester, _refreshButton(), settleAfterTap: false);
    await tester.pump();
    await held.$1.future;
    fixture.logs = [_auditItem(901, actor: 'fresh route return actor 原文')];

    final cover = MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('Audit route ABA cover')),
    );
    final navigator = fixture.navigatorKey.currentState!;
    final routeRevisionBefore = fixture.routeGate.routeRevision.value;
    unawaited(navigator.push<void>(cover));
    navigator.pop();
    expect(fixture.routeGate.routeRevision.value, routeRevisionBefore + 2);
    await tester.pumpAndSettle();

    final readsAfterReturn = fixture.auditReads.length;
    expect(readsAfterReturn, 3);
    expect(find.textContaining('fresh route return actor 原文'), findsOneWidget);
    staleSubmit('stale route query');
    staleChip(true);
    await tester.pumpAndSettle();
    expect(fixture.auditReads, hasLength(readsAfterReturn));

    held.$2.complete(
      _pageResponse([_auditItem(902, actor: 'stale route response actor 原文')]),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('fresh route return actor 原文'), findsOneWidget);
    expect(find.textContaining('stale route response actor 原文'), findsNothing);
    expect(fixture.auditReads, hasLength(readsAfterReturn));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Same-frame route ABA expires a retained Audit picker callback', (
    tester,
  ) async {
    final fixture = await _mountAudit(tester);
    final initialReads = fixture.auditReads.length;
    await tester.ensureVisible(_sortControl());
    await _tapHitTestableWidget(
      tester,
      _sortControl(),
      (widget) => widget is InkWell && widget.onTap != null,
    );
    final option = find.text('管理员 A-Z');
    final staleOptionTap = tester
        .widget<ListTile>(
          find.ancestor(of: option, matching: find.byType(ListTile)),
        )
        .onTap!;

    final cover = MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('Audit picker cover route')),
    );
    final navigator = fixture.navigatorKey.currentState!;
    final routeRevisionBefore = fixture.routeGate.routeRevision.value;
    unawaited(navigator.push<void>(cover));
    navigator.pop();
    expect(fixture.routeGate.routeRevision.value, routeRevisionBefore + 2);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('admin_audit_picker')), findsOneWidget);
    expect(option, findsOneWidget);
    staleOptionTap();
    await tester.pumpAndSettle();
    expect(fixture.auditReads, hasLength(initialReads));

    await _tapEnabledButton(tester, find.widgetWithText(TextButton, '取消'));
    expect(fixture.auditReads, hasLength(initialReads + 1));
    expect(fixture.auditReads.last.queryParameters['sort'], 'created_desc');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Held Audit success from a replaced client cannot publish old rows',
    (tester) async {
      final fixture = await _mountAudit(tester, holdInitialRead: true);
      await fixture.initialHeldAuditRead!.$1.future;
      expect(find.text('正在加载审计日志…'), findsOneWidget);
      I18n.setLocale(AppLocale.en);
      await tester.pump();
      expect(find.text('Loading audit log…'), findsOneWidget);
      expect(fixture.auditReads, hasLength(1));
      await _captureIfRequested(tester, fixture, 'audit-390-en-loading');
      I18n.setLocale(AppLocale.zh);
      await tester.pump();

      fixture.logs = [_auditItem(701, actor: 'replacement client actor 原文')];
      fixture.replaceClient();
      await tester.pumpAndSettle();
      expect(fixture.auditReads, hasLength(2));
      expect(
        find.textContaining('replacement client actor 原文'),
        findsOneWidget,
      );

      fixture.initialHeldAuditRead!.$2.complete(
        _pageResponse([_auditItem(702, actor: 'old client actor 原文')]),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('replacement client actor 原文'),
        findsOneWidget,
      );
      expect(find.textContaining('old client actor 原文'), findsNothing);
      expect(fixture.auditReads, hasLength(2));
    },
  );

  testWidgets(
    'In-place account session and token rotation expire held Audit data without notifying auth',
    (tester) async {
      final fixture = await _mountAudit(tester, holdInitialRead: true);
      await fixture.initialHeldAuditRead!.$1.future;
      fixture.logs = [_auditItem(711, actor: 'rotated token actor 原文')];
      fixture.auth.rotateSessionSnapshotWithoutNotify(
        'rotated-audit-token',
        userId: 'replacement-audit-admin',
      );
      fixture.initialHeldAuditRead!.$2.complete(
        _pageResponse([_auditItem(712, actor: 'expired token actor 原文')]),
      );
      await tester.pumpAndSettle();

      expect(fixture.auditReads, hasLength(2));
      expect(find.textContaining('rotated token actor 原文'), findsOneWidget);
      expect(find.textContaining('expired token actor 原文'), findsNothing);
      expect(
        fixture.auditReads.last.authorization,
        'Bearer rotated-audit-token',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Unnotified client token mismatch clears Audit rows without a fresh read',
    (tester) async {
      final fixture = await _mountAudit(tester);
      final staleRefresh = tester
          .widget<TextButton>(_refreshButton())
          .onPressed!;
      final readsBeforeRotation = fixture.auditReads.length;
      expect(find.textContaining('literal actor 原文 44'), findsOneWidget);

      fixture.auth.changeAuthorityWithoutNotify(
        clientToken: 'client-only-audit-token',
      );
      staleRefresh();
      await tester.pumpAndSettle();

      expect(fixture.auditReads, hasLength(readsBeforeRotation));
      expect(find.textContaining('literal actor 原文 44'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Unnotified base URL and permission change clears Audit error without a fresh read',
    (tester) async {
      final fixture = await _mountAudit(tester);
      fixture.failNextAuditReads = 1;
      await _returnToAuditTop(tester, target: _refreshButton());
      await _tapEnabledButton(tester, _refreshButton());

      const zhError = '无法加载审计日志：服务暂不可用，请稍后重试或联系管理员';
      final staleRefresh = tester
          .widget<TextButton>(_refreshButton())
          .onPressed!;
      await _scrollAuditUntilHitTestable(tester, find.text(zhError));
      expect(find.text(zhError), findsOneWidget);
      final readsBeforeRotation = fixture.auditReads.length;

      fixture.auth.changeAuthorityWithoutNotify(
        baseUrl: 'https://replacement.duoyi.test',
        permissions: const ['__none__'],
      );
      staleRefresh();
      await tester.pumpAndSettle();

      expect(fixture.auditReads, hasLength(readsBeforeRotation));
      expect(find.text(zhError), findsNothing);
      expect(find.textContaining('literal actor 原文 44'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Covered held Audit error is discarded and return starts a fresh read',
    (tester) async {
      final fixture = await _mountAudit(tester, holdInitialRead: true);
      await fixture.initialHeldAuditRead!.$1.future;
      final cover = MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Audit cover route')),
      );
      unawaited(fixture.navigatorKey.currentState!.push<void>(cover));
      await tester.pumpAndSettle();
      expect(find.text('Audit cover route'), findsOneWidget);

      fixture.navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();

      expect(fixture.auditReads, hasLength(2));
      expect(find.textContaining('literal actor 原文 44'), findsOneWidget);
      fixture.initialHeldAuditRead!.$2.complete(
        _json({'detail': 'held route error 原文'}, 500),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('held route error 原文'), findsNothing);
      expect(find.textContaining('literal actor 原文 44'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final layout in const [
    (width: 320.0, height: 720.0, textScale: 1.6, name: '320-1_6'),
    (width: 320.0, height: 720.0, textScale: 2.0, name: '320-2_0'),
    (width: 390.0, height: 540.0, textScale: 1.6, name: '390-short-1_6'),
    (width: 1200.0, height: 900.0, textScale: 1.0, name: '1200-desktop'),
  ]) {
    testWidgets('Audit list and filters fit ${layout.name}', (tester) async {
      final fixture = await _mountAudit(
        tester,
        width: layout.width,
        height: layout.height,
        textScale: layout.textScale,
      );
      expect(_searchField(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _captureIfRequested(
        tester,
        fixture,
        'audit-${layout.name}-zh-populated',
      );
      await _scrollAuditUntilHitTestable(tester, _nextPageButton());
      expect(
        find.byKey(const ValueKey('admin_audit_pagination_bar')),
        findsOneWidget,
      );
      expect(_nextPageButton(), findsOneWidget);
      await _tapEnabledButton(tester, _nextPageButton());
      expect(fixture.auditReads, hasLength(2));
      expect(fixture.auditReads.last.queryParameters['offset'], '20');
      await _scrollAuditUntilHitTestable(tester, _nextPageButton());
      await _captureIfRequested(
        tester,
        fixture,
        'audit-${layout.name}-zh-page2-footer',
      );
      await _returnToAuditTop(tester);
      expect(_searchField(), findsOneWidget);
      expect(_searchField().hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Audit layout remains reachable with a simulated IME inset', (
    tester,
  ) async {
    final fixture = await _mountAudit(
      tester,
      width: 390,
      height: 720,
      textScale: 1.4,
      viewInsetsBottom: 280,
    );
    expect(tester.view.viewInsets.bottom, 280);
    await tester.ensureVisible(_searchField());
    await _tapHitTestableWidget(
      tester,
      _searchField(),
      (widget) => widget is TextField && widget.enabled != false,
    );
    await tester.enterText(_searchField(), 'literal');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(fixture.auditReads, hasLength(2));

    await _scrollAuditUntilHitTestable(tester, _nextPageButton());
    await _captureIfRequested(
      tester,
      fixture,
      'audit-390-ime-inset-page1-footer',
    );
    await _tapEnabledButton(tester, _nextPageButton());
    expect(fixture.auditReads.last.queryParameters['offset'], '20');
    await _scrollAuditUntilHitTestable(tester, _nextPageButton());
    await _captureIfRequested(
      tester,
      fixture,
      'audit-390-ime-inset-page2-footer',
    );
    await _returnToAuditTop(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Audit dark desktop layout reaches and pages the footer', (
    tester,
  ) async {
    final fixture = await _mountAudit(
      tester,
      width: 1280,
      height: 900,
      dark: true,
    );
    await _scrollAuditUntilHitTestable(tester, _nextPageButton());
    expect(_nextPageButton(), findsOneWidget);
    await _tapEnabledButton(tester, _nextPageButton());
    expect(fixture.auditReads, hasLength(2));
    expect(fixture.auditReads.last.queryParameters['offset'], '20');
    await _scrollAuditUntilHitTestable(tester, _nextPageButton());
    await _captureIfRequested(tester, fixture, 'audit-1280-dark-page2-footer');
    await _returnToAuditTop(tester);
    expect(tester.takeException(), isNull);
  });
}

Finder _auditModule() => find.byKey(const ValueKey('admin-audit-0'));

Finder _searchField() => find.byKey(const ValueKey('admin_audit_search'));

Finder _sortControl() => find.byWidgetPredicate((widget) {
  final key = widget.key;
  if (key is! ValueKey) return false;
  final value = key.value;
  return value is (String, Object?) && value.$1 == 'admin-audit-sort';
});

Finder _clearSearchButton() => find.byWidgetPredicate(
  (widget) =>
      widget is IconButton &&
      (widget.tooltip == '清空日志搜索' || widget.tooltip == 'Clear audit search'),
);

Finder _refreshButton() => find.descendant(
  of: _auditModule(),
  matching: find.widgetWithIcon(TextButton, Icons.refresh),
);

Finder _nextPageButton() => find.descendant(
  of: find.byKey(const ValueKey('admin_audit_pagination_bar')),
  matching: find.widgetWithIcon(IconButton, Icons.chevron_right),
);

Finder _auditBodyScrollable() {
  final body = find.byKey(const ValueKey('admin_audit_body_scroll'));
  final nested = find.descendant(of: body, matching: find.byType(Scrollable));
  return nested.evaluate().isEmpty
      ? find
            .descendant(of: _auditModule(), matching: find.byType(Scrollable))
            .first
      : nested.first;
}

Future<void> _scrollAuditUntilHitTestable(
  WidgetTester tester,
  Finder target, {
  double delta = 220,
}) async {
  final scrollable = _auditBodyScrollable();
  await tester.scrollUntilVisible(target, delta, scrollable: scrollable);
  for (var attempt = 0; attempt < 48; attempt++) {
    await tester.pumpAndSettle();
    if (target.evaluate().isNotEmpty &&
        target.hitTestable().evaluate().isNotEmpty) {
      return;
    }
    await tester.drag(scrollable, Offset(0, -delta));
  }
  await tester.pumpAndSettle();
  expect(target, findsOneWidget);
  expect(target.hitTestable(), findsOneWidget);
}

Future<void> _returnToAuditTop(WidgetTester tester, {Finder? target}) async {
  final scrollable = _auditBodyScrollable();
  tester.state<ScrollableState>(scrollable).position.jumpTo(0);
  await tester.pumpAndSettle();
  final targetFinder = target ?? _searchField();
  expect(targetFinder, findsOneWidget);
  await tester.ensureVisible(targetFinder);
  await tester.pumpAndSettle();
  expect(targetFinder.hitTestable(), findsOneWidget);
}

Future<void> _tapEnabledButton(
  WidgetTester tester,
  Finder finder, {
  bool settleAfterTap = true,
}) async {
  await tester.pumpAndSettle();
  expect(finder, findsOneWidget);
  expect(finder.hitTestable(), findsOneWidget);
  final button = tester.widget<Widget>(finder);
  final VoidCallback? onPressed = switch (button) {
    TextButton value => value.onPressed,
    OutlinedButton value => value.onPressed,
    IconButton value => value.onPressed,
    _ => null,
  };
  expect(onPressed, isNotNull);
  await tester.tap(finder);
  if (settleAfterTap) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> _tapHitTestableWidget(
  WidgetTester tester,
  Finder finder,
  bool Function(Widget) canActivate,
) async {
  await tester.pumpAndSettle();
  expect(finder, findsOneWidget);
  expect(finder.hitTestable(), findsOneWidget);
  expect(canActivate(tester.widget<Widget>(finder)), isTrue);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void _expectLiteralAuditRow(
  WidgetTester tester,
  AppLocale locale,
  int index, {
  bool unknownAction = false,
}) {
  if (unknownAction) {
    expect(find.textContaining('future.action'), findsOneWidget);
  }
  expect(find.textContaining('literal actor 原文 $index'), findsOneWidget);
  expect(
    find.textContaining(
      locale == AppLocale.zh
          ? '对象：literal target 原文 $index'
          : 'Target: literal target 原文 $index',
    ),
    findsOneWidget,
  );
  expect(
    find.textContaining(
      locale == AppLocale.zh
          ? '详情：literal detail 原文 $index'
          : 'Details: literal detail 原文 $index',
    ),
    findsOneWidget,
  );
}

Future<_AuditFixture> _mountAudit(
  WidgetTester tester, {
  List<String> permissions = const ['audit'],
  double width = 390,
  double height = 900,
  double textScale = 1,
  double viewInsetsBottom = 0,
  bool dark = false,
  bool holdInitialRead = false,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  if (viewInsetsBottom > 0) {
    tester.view.viewInsets = FakeViewPadding(bottom: viewInsetsBottom);
  }
  addTearDown(tester.view.reset);
  await tester.runAsync(loadWidgetPolishScreenshotFonts);
  final fixture = _AuditFixture(permissions: permissions);
  if (holdInitialRead) {
    fixture.initialHeldAuditRead = fixture.holdNextAuditRead();
  }
  final baseTheme = widgetPolishScreenshotTheme();
  final theme = dark
      ? ThemeData(
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: baseTheme.colorScheme.primary,
            brightness: Brightness.dark,
          ),
          fontFamily: baseTheme.textTheme.bodyMedium?.fontFamily,
          fontFamilyFallback:
              baseTheme.textTheme.bodyMedium?.fontFamilyFallback,
        )
      : baseTheme;
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: fixture.auth),
      ],
      child: MaterialApp(
        navigatorKey: fixture.navigatorKey,
        navigatorObservers: [fixture.routeGate],
        scaffoldMessengerKey: fixture.messengerKey,
        theme: theme,
        builder: (context, child) => RepaintBoundary(
          key: fixture.screenshotKey,
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        ),
        home: const AdminScreen(initialTabIndex: 9),
      ),
    ),
  );
  if (holdInitialRead) {
    await tester.pump();
  } else {
    await tester.pumpAndSettle();
  }
  final auditAllowed =
      permissions.contains('audit') && !permissions.contains('__none__');
  if (auditAllowed) {
    expect(_auditModule(), findsOneWidget);
    if (holdInitialRead) {
      await fixture.initialHeldAuditRead!.$1.future;
    } else {
      expect(fixture.auditReads, hasLength(1));
    }
  } else {
    expect(_auditModule(), findsNothing);
    expect(fixture.auditReads, isEmpty);
  }
  expect(tester.takeException(), isNull);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });
  return fixture;
}

Future<void> _captureIfRequested(
  WidgetTester tester,
  _AuditFixture fixture,
  String name,
) async {
  final directoryPath =
      Platform.environment['DUOYI_ADMIN_AUDIT_SCREENSHOT_DIR'];
  if (directoryPath == null || directoryPath.trim().isEmpty) return;
  final requiredRoot = Directory(
    'evidence/screenshots/admin-audit-locale-20261014',
  ).absolute.path;
  final outputDirectory = Directory(directoryPath).absolute.path;
  if (outputDirectory != requiredRoot &&
      !outputDirectory.startsWith('$requiredRoot${Platform.pathSeparator}')) {
    throw StateError(
      'DUOYI_ADMIN_AUDIT_SCREENSHOT_DIR must stay under evidence/screenshots/admin-audit-locale-20261014/.',
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

class _AuditFixture {
  _AuditFixture({required List<String> permissions}) {
    logs = List.generate(45, (index) => _auditItem(index));
    auth = _SwitchableAuth(
      client: newClient(token: 'synthetic-audit-token'),
      state: _adminState(permissions: permissions),
    );
  }

  final List<_CapturedRequest> requests = [];
  final List<http.Client> transports = [];
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();
  final AppAccessRouteGate routeGate = AppAccessRouteGate();
  final GlobalKey screenshotKey = GlobalKey();
  late List<Map<String, dynamic>> logs;
  late final _SwitchableAuth auth;
  (Completer<void>, Completer<http.Response>)? initialHeldAuditRead;
  (Completer<void>, Completer<http.Response>)? _nextAuditRead;
  int failNextAuditReads = 0;

  List<_CapturedRequest> get auditReads => requests
      .where((request) => request.method == 'GET' && request.path == _auditPath)
      .toList();

  List<String> get requestLines =>
      requests.map((request) => request.line).toList();

  ApiClient newClient({required String token}) {
    final transport = MockClient(_handle);
    transports.add(transport);
    return ApiClient(
      baseUrl: 'https://duoyi.test',
      token: token,
      httpClient: transport,
    );
  }

  (Completer<void>, Completer<http.Response>) holdNextAuditRead() {
    final held = (Completer<void>(), Completer<http.Response>());
    _nextAuditRead = held;
    return held;
  }

  void replaceClient() {
    auth.replaceClient(newClient(token: auth.state.token ?? ''));
  }

  Future<http.Response> _handle(http.Request request) async {
    requests.add(
      _CapturedRequest(
        method: request.method,
        path: request.url.path,
        query: request.url.query,
        queryParameters: Map<String, String>.of(request.url.queryParameters),
        authorization: request.headers['authorization'] ?? '',
        host: request.url.host,
      ),
    );
    if (request.method == 'GET' && request.url.path == _auditPath) {
      final held = _nextAuditRead;
      _nextAuditRead = null;
      if (held != null) {
        held.$1.complete();
        return held.$2.future;
      }
      if (failNextAuditReads > 0) {
        failNextAuditReads--;
        return _json({'detail': 'literal audit failure'}, 500);
      }
      final query = request.url.queryParameters;
      final action = query['action'];
      final text = (query['q'] ?? '').toLowerCase();
      var matching = logs.where((item) {
        if (action != null && action.isNotEmpty && item['action'] != action) {
          return false;
        }
        if (text.isNotEmpty) {
          final haystack = [
            item['actor_name'],
            item['actor_id'],
            item['action'],
            item['target'],
            item['detail'],
          ].join(' ').toLowerCase();
          if (!haystack.contains(text)) return false;
        }
        return true;
      }).toList();
      switch (query['sort']) {
        case 'actor_asc':
          matching.sort(
            (a, b) => '${a['actor_name']}'.compareTo('${b['actor_name']}'),
          );
          break;
        case 'action_asc':
          matching.sort((a, b) => '${a['action']}'.compareTo('${b['action']}'));
          break;
        case 'target_asc':
          matching.sort((a, b) => '${a['target']}'.compareTo('${b['target']}'));
          break;
        default:
          matching.sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
      }
      final limit = int.tryParse(query['limit'] ?? '') ?? 20;
      final offset = int.tryParse(query['offset'] ?? '') ?? 0;
      final items = matching.skip(offset).take(limit).toList();
      return _json({
        'items': items,
        'total': matching.length,
        'limit': limit,
        'offset': offset,
        'has_more': offset + items.length < matching.length,
      });
    }
    if (request.method == 'GET') {
      final limit =
          int.tryParse(request.url.queryParameters['limit'] ?? '') ?? 20;
      final offset =
          int.tryParse(request.url.queryParameters['offset'] ?? '') ?? 0;
      return _json({
        'items': <Object>[],
        'total': 0,
        'limit': limit,
        'offset': offset,
        'has_more': false,
      });
    }
    return _json(<String, Object>{});
  }

  void dispose() {
    auth.dispose();
    for (final transport in transports) {
      transport.close();
    }
    routeGate.dispose();
  }
}

class _SwitchableAuth extends AuthProvider {
  _SwitchableAuth({required ApiClient client, required AuthState state})
    : _currentClient = client,
      _currentState = state,
      super(client: client, initialState: state);

  ApiClient _currentClient;
  AuthState _currentState;
  int _sessionGeneration = 0;

  @override
  ApiClient get client => _currentClient;

  @override
  AuthState get state => _currentState;

  @override
  int get sessionGeneration => _sessionGeneration;

  void replacePermissions(List<String> permissions) {
    _currentState = _currentState.copyWith(adminPermissions: permissions);
    notifyListeners();
  }

  void changeAuthorityWithoutNotify({
    String? clientToken,
    String? baseUrl,
    List<String>? permissions,
  }) {
    if (clientToken != null) _currentClient.token = clientToken;
    if (baseUrl != null) _currentClient.baseUrl = baseUrl;
    if (permissions != null) {
      _currentState = _currentState.copyWith(adminPermissions: permissions);
    }
  }

  void replaceClient(ApiClient client) {
    _currentClient = client;
    notifyListeners();
  }

  void rotateSessionSnapshotWithoutNotify(
    String token, {
    required String userId,
  }) {
    _currentClient.token = token;
    _currentState = _currentState.copyWith(token: token, userId: userId);
    _sessionGeneration++;
  }
}

AuthState _adminState({
  required List<String> permissions,
  String token = 'synthetic-audit-token',
}) => AuthState(
  userId: _selfId,
  username: 'literal-audit-admin',
  token: token,
  isAdmin: true,
  adminPermissions: permissions,
);

Map<String, dynamic> _auditItem(int index, {String? action, String? actor}) => {
  'id': index,
  'actor_id': 'literal-actor-id-$index',
  'actor_name': actor ?? 'literal actor 原文 $index',
  'action': action ?? (index == 43 ? 'future.action' : 'feedback.reply'),
  'target': 'literal target 原文 $index',
  'detail': 'literal detail 原文 $index',
  'created_at': '2026-10-14 08:${index.toString().padLeft(2, '0')}:00',
};

http.Response _pageResponse(List<Map<String, dynamic>> items) => _json({
  'items': items,
  'total': items.length,
  'limit': 20,
  'offset': 0,
  'has_more': false,
});

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);

class _CapturedRequest {
  const _CapturedRequest({
    required this.method,
    required this.path,
    required this.query,
    required this.queryParameters,
    required this.authorization,
    required this.host,
  });

  final String method;
  final String path;
  final String query;
  final Map<String, String> queryParameters;
  final String authorization;
  final String host;

  String get line => '$method $path${query.isEmpty ? '' : '?$query'}';
}
