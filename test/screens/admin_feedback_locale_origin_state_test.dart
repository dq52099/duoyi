import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/screens/admin_screen.dart';
import 'package:duoyi/services/admin_feedback_export.dart';
import 'package:duoyi/services/app_access_route_gate.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter/material.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import '../support/widget_polish_screenshot_font.dart';

const _feedbackPath = '/api/admin/feedback';
const _selfId = 'feedback-admin';

void main() {
  setUp(() => I18n.setLocale(AppLocale.zh));
  tearDown(() => I18n.setLocale(AppLocale.zh));

  testWidgets(
    'Feedback locale changes retain submitted filters, draft, focus, paging, and scroll without refetching',
    (tester) async {
      final fixture = await _mountFeedback(
        tester,
        items: List.generate(
          240,
          (index) => _feedbackItem(
            index + 1,
            username: 'literal user 原文 ${index + 1}',
            displayName: 'literal display 原文 ${index + 1}',
            content: 'literal feedback 原文 ${index + 1}',
            status: index.isEven ? 'open' : 'in_progress',
            category: index.isEven ? 'bug' : 'feature',
          ),
        ),
        total: 240,
      );

      await _tapChoiceChip(
        tester,
        find.byKey(const ValueKey('admin_feedback_status_open')),
      );
      await _tapChoiceChip(
        tester,
        find.byKey(const ValueKey('admin_feedback_category_bug')),
      );
      await tester.ensureVisible(_feedbackSearch());
      await tester.enterText(_feedbackSearch(), 'submitted query 原文');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      await _openFeedbackSort(tester, '用户 A-Z');
      await _openPageSize(tester, 50);
      await _returnToFeedbackFooter(tester, target: _nextFeedbackPage());
      await _tapEnabledButton(tester, _nextFeedbackPage());
      expect(fixture.feedbackReads.last.queryParameters, {
        'status': 'open',
        'q': 'submitted query 原文',
        'category': 'bug',
        'sort': 'user_asc',
        'limit': '50',
        'offset': '50',
      });
      await _returnToFeedbackTop(tester);

      await tester.enterText(_feedbackSearch(), 'unsent draft 原文');
      final field = tester.widget<TextField>(_feedbackSearch());
      final controller = field.controller!;
      controller.selection = const TextSelection(
        baseOffset: 2,
        extentOffset: 8,
      );
      final selection = controller.selection;
      final focusNode = tester
          .widget<EditableText>(
            find.descendant(
              of: _feedbackSearch(),
              matching: find.byType(EditableText),
            ),
          )
          .focusNode;
      expect(FocusManager.instance.primaryFocus, same(focusNode));

      final scrollState = _feedbackScrollState(tester);
      final maxScroll = scrollState.position.maxScrollExtent;
      if (maxScroll > 0) {
        scrollState.position.jumpTo(maxScroll.clamp(0.0, 64.0).toDouble());
        await tester.pumpAndSettle();
      }
      final scrollOffset = scrollState.position.pixels;
      expect(scrollOffset, greaterThan(0));
      final moduleElement = tester.element(_feedbackModule());
      final requestLines = List<String>.of(fixture.requestLines);

      for (final locale in [AppLocale.en, AppLocale.zh]) {
        I18n.setLocale(locale);
        await tester.pumpAndSettle();
        expect(tester.element(_feedbackModule()), same(moduleElement));
        expect(fixture.requestLines, requestLines);
        expect(controller.text, 'unsent draft 原文');
        expect(controller.selection, selection);
        expect(
          tester.widget<TextField>(_feedbackSearch()).controller,
          same(controller),
        );
        expect(FocusManager.instance.primaryFocus, same(focusNode));
        expect(scrollState.position.pixels, closeTo(scrollOffset, 0.01));
        expect(
          tester
              .widget<ChoiceChip>(
                find.byKey(const ValueKey('admin_feedback_status_open')),
              )
              .selected,
          isTrue,
        );
        expect(
          tester
              .widget<ChoiceChip>(
                find.byKey(const ValueKey('admin_feedback_category_bug')),
              )
              .selected,
          isTrue,
        );
        expect(
          _sortControlValue(tester),
          locale == AppLocale.zh ? '用户 A-Z' : 'User A–Z',
        );
        expect(fixture.feedbackReads.last.queryParameters, {
          'status': 'open',
          'q': 'submitted query 原文',
          'category': 'bug',
          'sort': 'user_asc',
          'limit': '50',
          'offset': '50',
        });
        expect(tester.takeException(), isNull);
        if (locale == AppLocale.en) {
          await _captureIfRequested(
            tester,
            fixture,
            'feedback-page-en-submitted-query-unsent-draft',
          );
        }
      }
      // The footer is lazy. Verify its locale after preserving the focused
      // header's draft and scroll above, then move to the footer explicitly.
      await _returnToFeedbackFooter(tester, target: _pageSizeButton(50));
      for (final locale in [AppLocale.en, AppLocale.zh]) {
        I18n.setLocale(locale);
        await tester.pumpAndSettle();
        expect(
          find.text(locale == AppLocale.zh ? '每页: 50' : 'Per page: 50'),
          findsOneWidget,
        );
        expect(fixture.requestLines, requestLines);
      }
    },
  );

  testWidgets(
    'Feedback list, detail, reply status picker, and confirmation localize labels while preserving server values',
    (tester) async {
      final items = [
        _feedbackItem(
          7,
          username: 'unknown-user 原文',
          displayName: '未知分类用户 原文',
          email: 'verified-true@example.invalid',
          emailVerified: true,
          category: 'future_category',
          status: 'future_status',
          content: 'future content 原文',
          adminReply: 'existing reply 原文',
        ),
        _feedbackItem(
          8,
          username: 'false-user 原文',
          email: 'verified-false@example.invalid',
          emailVerified: false,
          category: 'bug',
          status: 'open',
          content: 'known labels 原文',
        ),
        _feedbackItem(
          9,
          username: 'one-user 原文',
          email: 'verified-one@example.invalid',
          emailVerified: 1,
          category: 'feature',
          status: 'in_progress',
          content: 'numeric verified 原文',
        ),
        _feedbackItem(
          10,
          username: 'zero-user 原文',
          email: 'verified-zero@example.invalid',
          emailVerified: 0,
          category: 'wish',
          status: 'resolved',
          content: 'numeric unverified 原文',
        ),
      ];
      final fixture = await _mountFeedback(tester, items: items);

      expect(find.textContaining('future_category'), findsOneWidget);
      expect(find.textContaining('future_status'), findsOneWidget);
      expect(
        find.textContaining('verified-true@example.invalid (已验证)'),
        findsOneWidget,
      );
      expect(
        find.textContaining('verified-false@example.invalid (未验证)'),
        findsOneWidget,
      );
      expect(
        find.textContaining('verified-one@example.invalid (已验证)'),
        findsOneWidget,
      );
      expect(
        find.textContaining('verified-zero@example.invalid (未验证)'),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _feedbackCard(8),
          matching: find.textContaining('问题反馈'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _feedbackCard(9),
          matching: find.textContaining('功能建议'),
        ),
        findsOneWidget,
      );
      await _captureIfRequested(
        tester,
        fixture,
        'feedback-list-zh-unknown-values',
      );

      await tester.ensureVisible(find.text('future content 原文'));
      await tester.tap(find.text('future content 原文'));
      await tester.pumpAndSettle();
      final detail = find.byKey(const ValueKey('admin_feedback_detail_dialog'));
      expect(detail, findsOneWidget);
      expect(
        find.descendant(
          of: detail,
          matching: find.textContaining('future_category'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: detail,
          matching: find.textContaining('future_status'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: detail,
          matching: find.textContaining('verified-true@example.invalid (已验证)'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: detail,
          matching: find.textContaining('existing reply 原文'),
        ),
        findsOneWidget,
      );
      await _captureIfRequested(
        tester,
        fixture,
        'feedback-detail-zh-unknown-values',
      );

      I18n.setLocale(
        I18n.current == AppLocale.zh ? AppLocale.en : AppLocale.zh,
      );
      await tester.pumpAndSettle();
      expect(find.text('Feedback details'), findsOneWidget);
      expect(find.text('Category'), findsOneWidget);
      expect(find.text('Status'), findsOneWidget);
      expect(
        find.descendant(
          of: detail,
          matching: find.textContaining('future_category'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: detail,
          matching: find.textContaining('future_status'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: detail,
          matching: find.textContaining(
            'verified-true@example.invalid (verified)',
          ),
        ),
        findsOneWidget,
      );
      await _tapDialogButton(
        tester,
        detail,
        find.widgetWithText(TextButton, 'Close'),
      );

      await _openFeedbackAction(
        tester,
        7,
        icon: Icons.reply_outlined,
        tooltip: 'Reply',
      );
      final replyDialog = find.byKey(
        const ValueKey('admin_feedback_reply_dialog'),
      );
      expect(replyDialog, findsOneWidget);
      expect(
        find.descendant(
          of: replyDialog,
          matching: find.textContaining('future content 原文'),
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(_replyField()).controller!.text,
        'existing reply 原文',
      );
      expect(
        find.descendant(of: replyDialog, matching: find.text('future_status')),
        findsOneWidget,
      );
      await _captureIfRequested(
        tester,
        fixture,
        'feedback-reply-en-unknown-status',
      );

      await _tapHitTestableWidget(
        tester,
        _replyStatusControl(),
        (widget) => widget is InkWell && widget.onTap != null,
      );
      final picker = find.byKey(const ValueKey('admin_feedback_picker'));
      expect(picker, findsOneWidget);
      expect(
        find.descendant(of: picker, matching: find.text('future_status')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: picker, matching: find.text('In progress')),
        findsOneWidget,
      );
      I18n.setLocale(AppLocale.zh);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: picker, matching: find.text('future_status')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: picker, matching: find.text('处理中')),
        findsOneWidget,
      );
      await _captureIfRequested(
        tester,
        fixture,
        'feedback-reply-status-picker-zh',
      );
      await _tapPickerOption(tester, picker, '处理中');
      expect(
        find.descendant(of: replyDialog, matching: find.text('处理中')),
        findsOneWidget,
      );
      await _tapDialogButton(
        tester,
        replyDialog,
        find.widgetWithText(TextButton, '取消'),
      );

      await _openFeedbackAction(
        tester,
        7,
        icon: Icons.inventory_2_outlined,
        tooltip: '关闭',
      );
      final confirmation = find.text('关闭反馈？');
      expect(confirmation, findsOneWidget);
      expect(find.textContaining('将把 未知分类用户 原文 的这条反馈标记为已关闭。'), findsOneWidget);
      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      expect(find.text('Close feedback?'), findsOneWidget);
      expect(
        find.textContaining('Mark this feedback from 未知分类用户 原文 as closed?'),
        findsOneWidget,
      );
      await _captureIfRequested(tester, fixture, 'feedback-close-confirm-en');
      final cancel = find.widgetWithText(TextButton, 'Cancel');
      await _tapEnabledButton(tester, cancel);
      expect(fixture.feedbackWrites, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Feedback access requires the exact permission and honors none', (
    tester,
  ) async {
    for (final permissions in [
      const ['feedback'],
      const ['users'],
      const ['audit'],
      const ['__none__'],
      const ['*', '__none__'],
    ]) {
      final fixture = await _mountFeedback(tester, permissions: permissions);
      final allowed =
          permissions.contains('feedback') && !permissions.contains('__none__');
      if (allowed) {
        expect(_feedbackModule(), findsOneWidget, reason: '$permissions');
        expect(fixture.feedbackReads, hasLength(1), reason: '$permissions');
      } else {
        expect(_feedbackModule(), findsNothing, reason: '$permissions');
        expect(fixture.feedbackReads, isEmpty, reason: '$permissions');
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      fixture.dispose();
    }
  });

  testWidgets(
    'Silent Feedback permission revocation hides the tab and blocks a retained callback',
    (tester) async {
      final fixture = await _mountFeedback(tester);
      final staleRefresh = tester
          .widget<TextButton>(_feedbackRefreshButton())
          .onPressed!;
      expect(fixture.feedbackReads, hasLength(1));

      fixture.auth.replacePermissionsWithoutNotify(const ['__none__']);
      staleRefresh();
      await tester.pumpAndSettle();

      expect(find.textContaining('literal feedback 原文 1'), findsNothing);
      expect(_feedbackSearch(), findsNothing);
      expect(_feedbackRefreshButton(), findsNothing);
      expect(
        find.descendant(
          of: _feedbackModule(),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsNothing,
      );
      expect(find.text('正在加载反馈列表…'), findsNothing);
      expect(fixture.feedbackReads, hasLength(1));
      expect(fixture.feedbackWrites, isEmpty);

      fixture.auth.replacePermissions(const ['feedback']);
      await tester.pumpAndSettle();

      expect(_feedbackSearch(), findsOneWidget);
      expect(find.textContaining('literal feedback 原文 1'), findsOneWidget);
      expect(fixture.feedbackReads, hasLength(2));
      expect(fixture.feedbackWrites, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Feedback same-frame route ABA ignores held rows and retained controls',
    (tester) async {
      final fixture = await _mountFeedback(tester);
      final staleSubmit = tester
          .widget<TextField>(_feedbackSearch())
          .onSubmitted!;
      final staleStatus = tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('admin_feedback_status_open')),
          )
          .onSelected!;
      final staleRefresh = tester
          .widget<TextButton>(_feedbackRefreshButton())
          .onPressed!;
      final held = fixture.holdNextPageRead();
      await _tapEnabledButton(
        tester,
        _feedbackRefreshButton(),
        settleAfterTap: false,
      );
      await held.$1.future;

      final cover = MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Feedback route ABA cover')),
      );
      final navigator = fixture.navigatorKey.currentState!;
      final revisionBefore = fixture.routeGate.routeRevision.value;
      unawaited(navigator.push<void>(cover));
      navigator.pop();
      expect(fixture.routeGate.routeRevision.value, revisionBefore + 2);
      await tester.pumpAndSettle();
      final readsAfterReturn = fixture.feedbackReads.length;
      expect(readsAfterReturn, 3);
      expect(find.textContaining('literal feedback 原文 1'), findsOneWidget);

      staleSubmit('stale route query');
      staleStatus(true);
      staleRefresh();
      await tester.pumpAndSettle();
      expect(fixture.feedbackReads, hasLength(readsAfterReturn));
      expect(
        fixture.requests.where((request) => request.path == '/api/config'),
        isEmpty,
      );

      held.$2.complete(
        _pageResponse(
          [_feedbackItem(999, content: 'stale route response 原文')],
          total: 1,
          limit: 20,
          offset: 0,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('stale route response 原文'), findsNothing);
      expect(find.textContaining('literal feedback 原文 1'), findsOneWidget);
      expect(fixture.feedbackReads, hasLength(readsAfterReturn));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Feedback same-frame tab ABA ignores a held page response', (
    tester,
  ) async {
    final fixture = await _mountFeedback(tester);
    final staleSubmit = tester
        .widget<TextField>(_feedbackSearch())
        .onSubmitted!;
    final staleRefresh = tester
        .widget<TextButton>(_feedbackRefreshButton())
        .onPressed!;
    final held = fixture.holdNextPageRead();
    await _tapEnabledButton(
      tester,
      _feedbackRefreshButton(),
      settleAfterTap: false,
    );
    await held.$1.future;

    final tabs = tester.widget<TabBar>(find.byType(TabBar).first).controller!;
    tabs.index = 8;
    tabs.index = 7;
    await tester.pumpAndSettle();
    final readsAfterReturn = fixture.feedbackReads.length;
    expect(readsAfterReturn, 3);
    staleSubmit('stale tab query');
    staleRefresh();
    await tester.pumpAndSettle();
    expect(fixture.feedbackReads, hasLength(readsAfterReturn));

    // TabBarView coalesces same-frame warps even though the TabController
    // already reports 7. Restore its physical page through a normal round trip
    // before testing the old response against the visible fresh page.
    tabs.index = 8;
    await tester.pumpAndSettle();
    tabs.index = 7;
    await tester.pumpAndSettle();
    expect(fixture.feedbackReads, hasLength(readsAfterReturn + 1));
    held.$2.complete(
      _pageResponse(
        [_feedbackItem(998, content: 'stale tab response 原文')],
        total: 1,
        limit: 20,
        offset: 0,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('stale tab response 原文'), findsNothing);
    await _scrollFeedbackUntilHitTestable(tester, _feedbackCard(1));
    expect(find.text('literal feedback 原文 1'), findsOneWidget);
    expect(fixture.feedbackReads, hasLength(readsAfterReturn + 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Retained Feedback retry expires after permission revoke/regrant ABA',
    (tester) async {
      final fixture = await _mountFeedback(tester);
      fixture.failNextPageReads = 1;
      await _tapEnabledButton(tester, _feedbackRefreshButton());
      expect(fixture.feedbackReads, hasLength(2));
      final retry = _feedbackRetryButton();
      await _scrollFeedbackUntilHitTestable(tester, retry);
      final staleRetry = tester.widget<OutlinedButton>(retry).onPressed!;
      fixture.auth.replacePermissions(const ['__none__']);
      fixture.auth.replacePermissions(const ['feedback']);
      await tester.pumpAndSettle();
      final readsAfterRegrant = fixture.feedbackReads.length;

      staleRetry();
      await tester.pumpAndSettle();
      expect(fixture.feedbackReads, hasLength(readsAfterRegrant));
      expect(find.byKey(const ValueKey('admin_feedback_picker')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Silent client, token, and base URL changes clear Feedback data', (
    tester,
  ) async {
    for (final change in ['client', 'token', 'baseUrl']) {
      final fixture = await _mountFeedback(
        tester,
        items: [_feedbackItem(1, content: 'old private row 原文')],
      );
      final staleRefresh = tester
          .widget<TextButton>(_feedbackRefreshButton())
          .onPressed!;
      expect(find.textContaining('old private row 原文'), findsOneWidget);
      fixture.items = [_feedbackItem(2, content: 'fresh authority row 原文')];
      final held = fixture.holdNextPageRead();
      switch (change) {
        case 'client':
          fixture.auth.replaceClientSilently(
            fixture.newClient(
              token: 'replacement-client-token',
              baseUrl: 'https://replacement-client.duoyi.test',
            ),
            token: 'replacement-client-token',
          );
          break;
        case 'token':
          fixture.auth.rotateSessionSnapshotWithoutNotify(
            'replacement-token',
            userId: 'replacement-token-admin',
          );
          break;
        case 'baseUrl':
          fixture.auth.changeAuthorityWithoutNotify(
            baseUrl: 'https://replacement-base.duoyi.test',
          );
          break;
      }

      // Rebuild the real AdminScreen with the silently replaced provider client.
      I18n.setLocale(
        I18n.current == AppLocale.zh ? AppLocale.en : AppLocale.zh,
      );
      await tester.pump();
      staleRefresh();
      // A held first-page read has an indeterminate spinner. Settling here
      // advances the fake clock until HTTP timeout instead of awaiting dispatch.
      await tester.pump(const Duration(milliseconds: 50));
      await held.$1.future;
      expect(find.textContaining('old private row 原文'), findsNothing);
      expect(find.textContaining('fresh authority row 原文'), findsNothing);
      final newRead = fixture.feedbackReads.last;
      switch (change) {
        case 'client':
          expect(newRead.host, 'replacement-client.duoyi.test');
          expect(newRead.authorization, 'Bearer replacement-client-token');
          break;
        case 'token':
          expect(newRead.host, 'duoyi.test');
          expect(newRead.authorization, 'Bearer replacement-token');
          break;
        case 'baseUrl':
          expect(newRead.host, 'replacement-base.duoyi.test');
          expect(newRead.authorization, 'Bearer synthetic-feedback-token');
          break;
      }

      held.$2.complete(
        _pageResponse(
          [_feedbackItem(2, content: 'fresh authority row 原文')],
          total: 1,
          limit: 20,
          offset: 0,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('old private row 原文'), findsNothing);
      await _scrollFeedbackUntilHitTestable(tester, _feedbackCard(2));
      expect(find.text('fresh authority row 原文'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      fixture.dispose();
    }
  });

  for (final exitMode in const ['closed', 'covered']) {
    testWidgets('Held Feedback detail cannot publish after it is $exitMode', (
      tester,
    ) async {
      final fixture = await _mountFeedback(tester);
      final held = fixture.holdNextDetailRead(7);
      await _scrollFeedbackUntilHitTestable(tester, _feedbackCard(7));
      await tester.ensureVisible(find.text('literal feedback 原文 7'));
      await tester.tap(find.text('literal feedback 原文 7'));
      await tester.pump();
      await held.$1.future;
      expect(
        find.byKey(const ValueKey('admin_feedback_detail_dialog')),
        findsOneWidget,
      );

      if (exitMode == 'closed') {
        final detail = find.byKey(
          const ValueKey('admin_feedback_detail_dialog'),
        );
        await _tapDialogButton(
          tester,
          detail,
          find.widgetWithText(TextButton, '关闭'),
        );
      } else {
        final cover = MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Covered Feedback detail')),
        );
        unawaited(fixture.navigatorKey.currentState!.push<void>(cover));
        await tester.pumpAndSettle();
        expect(find.text('Covered Feedback detail'), findsOneWidget);
      }

      held.$2.complete(
        _json({
          ..._feedbackItem(7),
          'content': 'late full detail must stay hidden 原文',
        }),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'late full detail must stay hidden 原文',
          skipOffstage: false,
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'Canceled Feedback reply cannot save or pop a reopened editor; duplicate save writes once',
    (tester) async {
      final fixture = await _mountFeedback(tester);
      await _openFeedbackAction(
        tester,
        7,
        icon: Icons.reply_outlined,
        tooltip: '回复',
      );
      await tester.enterText(_replyField(), 'old canceled reply 原文');
      final firstDialog = find.byKey(
        const ValueKey('admin_feedback_reply_dialog'),
      );
      final staleSave = tester
          .widget<FilledButton>(_replySubmitButton(firstDialog))
          .onPressed!;
      await _tapDialogButton(
        tester,
        firstDialog,
        find.widgetWithText(TextButton, '取消'),
      );

      await _openFeedbackAction(
        tester,
        7,
        icon: Icons.reply_outlined,
        tooltip: '回复',
      );
      final secondDialog = find.byKey(
        const ValueKey('admin_feedback_reply_dialog'),
      );
      expect(secondDialog, findsOneWidget);
      staleSave();
      await tester.pumpAndSettle();
      expect(secondDialog, findsOneWidget);
      expect(fixture.feedbackWrites, isEmpty);

      await tester.enterText(_replyField(), 'new submitted reply 原文');
      final submit = _replySubmitButton(secondDialog);
      final save = tester.widget<FilledButton>(submit).onPressed!;
      await tester.pumpAndSettle();
      expect(submit.hitTestable(), findsOneWidget);
      await tester.tap(submit);
      save();
      await tester.pumpAndSettle();

      expect(fixture.feedbackWrites, hasLength(1));
      expect(fixture.feedbackWrites.single.path, '/api/admin/feedback/reply');
      expect(jsonDecode(fixture.feedbackWrites.single.body), {
        'feedback_id': 7,
        'reply': 'new submitted reply 原文',
        'status': 'open',
      });
      expect(fixture.feedbackReads, hasLength(2));
      expect(find.text('反馈已回复'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Nested Feedback reply status selection and cancellation preserve draft; save writes once',
    (tester) async {
      final fixture = await _mountFeedback(tester);
      await _openFeedbackAction(
        tester,
        7,
        icon: Icons.reply_outlined,
        tooltip: '回复',
      );
      final replyDialog = find.byKey(
        const ValueKey('admin_feedback_reply_dialog'),
      );
      const draft = 'nested status reply draft 原文';
      await tester.enterText(_replyField(), draft);

      await _tapHitTestableWidget(
        tester,
        _replyStatusControl(),
        (widget) => widget is InkWell && widget.onTap != null,
      );
      final picker = find.byKey(const ValueKey('admin_feedback_picker'));
      await _tapPickerOption(tester, picker, '处理中');
      expect(replyDialog, findsOneWidget);
      expect(tester.widget<TextField>(_replyField()).controller!.text, draft);
      expect(
        find.descendant(of: replyDialog, matching: find.text('处理中')),
        findsOneWidget,
      );
      expect(fixture.feedbackWrites, isEmpty);

      await _tapHitTestableWidget(
        tester,
        _replyStatusControl(),
        (widget) => widget is InkWell && widget.onTap != null,
      );
      final cancelPicker = find.descendant(
        of: find.byKey(const ValueKey('admin_feedback_picker')),
        matching: find.widgetWithText(TextButton, '取消'),
      );
      await _tapEnabledButton(tester, cancelPicker);
      expect(find.byKey(const ValueKey('admin_feedback_picker')), findsNothing);
      expect(replyDialog, findsOneWidget);
      expect(tester.widget<TextField>(_replyField()).controller!.text, draft);
      expect(
        find.descendant(of: replyDialog, matching: find.text('处理中')),
        findsOneWidget,
      );

      await _tapEnabledButton(tester, _replySubmitButton(replyDialog));
      expect(fixture.feedbackWrites, hasLength(1));
      expect(fixture.feedbackWrites.single.method, 'POST');
      expect(fixture.feedbackWrites.single.path, '/api/admin/feedback/reply');
      expect(jsonDecode(fixture.feedbackWrites.single.body), {
        'feedback_id': 7,
        'reply': draft,
        'status': 'in_progress',
      });
      expect(fixture.feedbackReads, hasLength(2));
      expect(find.text('反馈已回复'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Feedback reply authority cannot revive when the nested picker exits',
    (tester) async {
      final fixture = await _mountFeedback(tester);
      await _openFeedbackAction(
        tester,
        7,
        icon: Icons.reply_outlined,
        tooltip: '回复',
      );
      final replyDialog = find.byKey(
        const ValueKey('admin_feedback_reply_dialog'),
      );
      const draft = 'revoked nested picker reply draft 原文';
      await tester.enterText(_replyField(), draft);
      final staleSave = tester
          .widget<FilledButton>(_replySubmitButton(replyDialog))
          .onPressed!;
      await _tapHitTestableWidget(
        tester,
        _replyStatusControl(),
        (widget) => widget is InkWell && widget.onTap != null,
      );

      final selectorRoute =
          fixture.routeGate.currentRoute! as ModalRoute<dynamic>;
      final selectorCompleted = Completer<void>();
      unawaited(
        selectorRoute.completed.then((_) {
          if (!selectorCompleted.isCompleted) selectorCompleted.complete();
        }),
      );
      final parentRoute = ModalRoute.of(tester.element(replyDialog))!;
      fixture.navigatorKey.currentState!.pop('in_progress');
      await tester.pump(const Duration(milliseconds: 16));
      expect(selectorCompleted.isCompleted, isFalse);
      staleSave();
      await tester.pump();
      expect(selectorCompleted.isCompleted, isFalse);
      expect(parentRoute.isActive, isTrue);
      expect(parentRoute.isCurrent, isTrue);
      expect(replyDialog, findsOneWidget);
      expect(tester.widget<TextField>(_replyField()).controller!.text, draft);
      expect(fixture.feedbackWrites, isEmpty);

      fixture.auth.replacePermissions(const ['__none__']);
      fixture.auth.replacePermissions(const ['feedback']);
      await tester.pump();
      expect(selectorCompleted.isCompleted, isFalse);
      // The expired parent still covers a pending recovery spinner. Complete
      // only this exit animation; settling waits until that parent is closed.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(selectorCompleted.isCompleted, isTrue);
      expect(selectorRoute.isActive, isFalse);
      expect(find.byKey(const ValueKey('admin_feedback_picker')), findsNothing);
      expect(replyDialog, findsNothing);
      expect(_replyField(), findsNothing);
      expect(find.text(draft), findsNothing);
      expect(find.text('操作已失效'), findsOneWidget);
      staleSave();
      await tester.pump();
      expect(fixture.feedbackWrites, isEmpty);
      expect(fixture.feedbackReads, hasLength(1));
      final close = find.widgetWithText(TextButton, '关闭').hitTestable();
      expect(close, findsOneWidget);
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(fixture.feedbackReads, hasLength(2));
      expect(fixture.feedbackWrites, isEmpty);
      expect(find.text(draft), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Expired Feedback reply write does not trigger stale refresh or notice',
    (tester) async {
      final fixture = await _mountFeedback(tester);
      await _openFeedbackAction(
        tester,
        7,
        icon: Icons.reply_outlined,
        tooltip: '回复',
      );
      await tester.enterText(_replyField(), 'held reply 原文');
      final held = fixture.holdNextWrite();
      await _tapEnabledButton(
        tester,
        _replySubmitButton(
          find.byKey(const ValueKey('admin_feedback_reply_dialog')),
        ),
      );
      await held.$1.future;
      expect(fixture.feedbackWrites, hasLength(1));

      fixture.auth.rotateSessionSnapshotWithoutNotify(
        'rotated-feedback-token',
        userId: 'rotated-feedback-admin',
      );
      held.$2.complete(_json({'status': 'ok'}));
      await tester.pumpAndSettle();

      expect(fixture.feedbackWrites, hasLength(1));
      expect(
        fixture.feedbackReads.where(
          (request) => request.authorization == 'Bearer rotated-feedback-token',
        ),
        hasLength(1),
      );
      expect(find.text('反馈已回复'), findsNothing);
      expect(find.text('Reply saved'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Successful Feedback write reports saved when refresh fails; retry does not rewrite',
    (tester) async {
      final fixture = await _mountFeedback(tester);
      fixture.failNextPageReads = 1;
      await _openFeedbackAction(
        tester,
        7,
        icon: Icons.reply_outlined,
        tooltip: '回复',
      );
      await tester.enterText(_replyField(), 'saved despite refresh failure 原文');
      await _tapEnabledButton(
        tester,
        _replySubmitButton(
          find.byKey(const ValueKey('admin_feedback_reply_dialog')),
        ),
      );
      await tester.pumpAndSettle();

      expect(fixture.feedbackWrites, hasLength(1));
      expect(fixture.feedbackReads, hasLength(2));
      expect(find.textContaining('反馈已回复，但列表刷新失败，请刷新后查看。'), findsOneWidget);
      final retry = _feedbackRetryButton();
      await _tapEnabledButton(tester, retry);
      expect(fixture.feedbackWrites, hasLength(1));
      expect(fixture.feedbackReads, hasLength(3));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Feedback empty-page fallback retry keeps the query tuple at the new last offset',
    (tester) async {
      final fixture = await _mountFeedback(
        tester,
        items: List.generate(
          120,
          (index) => _feedbackItem(index + 1, category: 'bug', status: 'open'),
        ),
        total: 120,
      );
      await _tapChoiceChip(
        tester,
        find.byKey(const ValueKey('admin_feedback_status_open')),
      );
      await _tapChoiceChip(
        tester,
        find.byKey(const ValueKey('admin_feedback_category_bug')),
      );
      await tester.ensureVisible(_feedbackSearch());
      await tester.enterText(_feedbackSearch(), 'shrinking result 原文');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      await _openFeedbackSort(tester, '用户 A-Z');
      await _openPageSize(tester, 50);
      await _returnToFeedbackFooter(tester, target: _nextFeedbackPage());
      await _tapEnabledButton(tester, _nextFeedbackPage());
      await _returnToFeedbackFooter(tester, target: _nextFeedbackPage());
      await _tapEnabledButton(tester, _nextFeedbackPage());

      const queryAtCurrentOffset = {
        'status': 'open',
        'q': 'shrinking result 原文',
        'category': 'bug',
        'sort': 'user_asc',
        'limit': '50',
        'offset': '100',
      };
      expect(fixture.feedbackReads.last.queryParameters, queryAtCurrentOffset);
      final readsBeforeRefresh = fixture.feedbackReads.length;
      final held = fixture.holdNextPageRead();
      await _returnToFeedbackTop(tester, target: _feedbackRefreshButton());
      await _tapEnabledButton(
        tester,
        _feedbackRefreshButton(),
        settleAfterTap: false,
      );
      await held.$1.future;
      expect(fixture.feedbackReads, hasLength(readsBeforeRefresh + 1));
      expect(fixture.feedbackReads.last.queryParameters, queryAtCurrentOffset);

      fixture.total = 87;
      fixture.items = fixture.items.take(87).toList();
      fixture.failNextPageReads = 1;
      held.$2.complete(
        _pageResponse(const [], total: 87, limit: 50, offset: 100),
      );
      await tester.pumpAndSettle();

      expect(fixture.feedbackReads, hasLength(readsBeforeRefresh + 2));
      expect(fixture.feedbackReads.last.queryParameters, {
        ...queryAtCurrentOffset,
        'offset': '50',
      });
      expect(_feedbackRetryButton(), findsOneWidget);
      expect(fixture.feedbackWrites, isEmpty);
      await _scrollFeedbackUntilHitTestable(tester, _feedbackRetryButton());
      await _tapEnabledButton(tester, _feedbackRetryButton());
      expect(fixture.feedbackReads, hasLength(readsBeforeRefresh + 3));
      expect(fixture.feedbackReads.last.queryParameters, {
        ...queryAtCurrentOffset,
        'offset': '50',
      });
      expect(fixture.feedbackWrites, isEmpty);
      await _scrollFeedbackUntilHitTestable(
        tester,
        find.textContaining('literal feedback 原文 51'),
      );
      expect(find.textContaining('literal feedback 原文 51'), findsOneWidget);
      await _scrollFeedbackUntilHitTestable(
        tester,
        find.textContaining('literal feedback 原文 87'),
      );
      expect(find.textContaining('literal feedback 原文 87'), findsOneWidget);
      expect(find.textContaining('literal feedback 原文 88'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Deleting the only Feedback item on a nonzero page reloads the previous offset',
    (tester) async {
      final fixture = await _mountFeedback(
        tester,
        items: List.generate(41, (index) => _feedbackItem(index + 1)),
        total: 41,
      );
      await _returnToFeedbackFooter(tester, target: _nextFeedbackPage());
      await _tapEnabledButton(tester, _nextFeedbackPage());
      await _returnToFeedbackFooter(tester, target: _nextFeedbackPage());
      await _tapEnabledButton(tester, _nextFeedbackPage());
      expect(find.textContaining('literal feedback 原文 41'), findsOneWidget);
      expect(fixture.feedbackReads.last.queryParameters['offset'], '40');

      await _openFeedbackAction(
        tester,
        41,
        icon: Icons.delete_outline,
        tooltip: '删除',
      );
      expect(find.text('删除反馈？'), findsOneWidget);
      await _tapEnabledButton(tester, find.widgetWithText(FilledButton, '删除'));

      expect(fixture.feedbackWrites, hasLength(1));
      expect(fixture.feedbackWrites.single.method, 'DELETE');
      expect(fixture.feedbackWrites.single.path, '/api/admin/feedback/41');
      expect(fixture.feedbackReads.last.queryParameters, {
        'sort': 'created_desc',
        'limit': '20',
        'offset': '20',
      });
      expect(fixture.items, hasLength(40));
      expect(find.textContaining('literal feedback 原文 41'), findsNothing);
      await _scrollFeedbackUntilHitTestable(
        tester,
        find.textContaining('literal feedback 原文 21'),
      );
      expect(find.textContaining('literal feedback 原文 21'), findsOneWidget);
      await _scrollFeedbackUntilHitTestable(
        tester,
        find.textContaining('literal feedback 原文 40'),
      );
      expect(find.textContaining('literal feedback 原文 40'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Feedback bulk action sends exactly 100 and blocks 101 or 200 current-page rows',
    (tester) async {
      for (final count in const [100, 101, 200]) {
        final fixture = await _mountFeedback(
          tester,
          width: 1280,
          items: List.generate(
            count,
            (index) => _feedbackItem(
              index + 1,
              username: 'bulk user ${index + 1}',
              content: 'bulk feedback ${index + 1}',
              status: 'open',
            ),
          ),
          total: count,
        );
        await _openPageSize(tester, count == 100 ? 100 : 200);
        await _returnToFeedbackTop(tester);
        expect(
          fixture.feedbackReads.last.queryParameters['limit'],
          count == 100 ? '100' : '200',
        );
        expect(find.textContaining('本页 $count 条 · 待处理 $count'), findsOneWidget);
        final bulk = find.widgetWithText(TextButton, '本页待处理转处理中');
        await _scrollFeedbackUntilHitTestable(tester, bulk);
        final bulkButton = tester.widget<TextButton>(bulk);
        if (count == 100) {
          expect(bulkButton.onPressed, isNotNull);
          await _tapEnabledButton(tester, bulk);
          expect(find.text('批量处理反馈？'), findsOneWidget);
          await _tapEnabledButton(
            tester,
            find.widgetWithText(FilledButton, '提交'),
          );
          expect(fixture.feedbackWrites, hasLength(1));
          expect(
            fixture.feedbackWrites.single.path,
            '/api/admin/feedback/bulk-status',
          );
          final payload =
              jsonDecode(fixture.feedbackWrites.single.body)
                  as Map<String, dynamic>;
          expect(
            (payload['feedback_ids'] as List),
            List<int>.generate(100, (i) => i + 1),
          );
          expect(payload['status'], 'in_progress');
        } else {
          expect(bulkButton.onPressed, isNull);
          expect(find.textContaining('每次最多处理 100 条'), findsOneWidget);
          expect(fixture.feedbackWrites, isEmpty);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        fixture.dispose();
      }
    },
  );

  testWidgets(
    'Feedback export uses the injected effect chain once and preserves CSV/path/share copy',
    (tester) async {
      final effects = _FakeFeedbackExportEffects();
      final fixture = await _mountFeedback(
        tester,
        width: 1280,
        exportEffects: effects,
      );
      final exportButton = _feedbackExportButton('导出筛选结果');
      await _tapEnabledButton(tester, exportButton);

      expect(fixture.exportReads, hasLength(1));
      expect(fixture.exportReads.single.queryParameters, {
        'sort': 'created_desc',
        'limit': '5000',
      });
      final file = effects.allocatedFiles.single;
      expect(effects.calls, [
        'temporaryDirectory',
        'allocate',
        'write',
        'copyPath',
        'share',
      ]);
      expect(
        effects.writtenCsv.single,
        // Preserve ApiClient.getText's existing UTF-8 BOM decoding.
        'id,title\n7,literal feedback 原文 7\n',
      );
      expect(effects.copiedPaths, [file.path]);
      expect(effects.sharedFiles, [file]);
      expect(effects.sharedTexts, ['多仪管理员反馈导出']);
      expect(effects.sharedSubjects, ['多仪反馈 CSV']);
      expect(effects.cleanedFiles, isEmpty);
      expect(find.textContaining(file.path), findsOneWidget);
      await _captureIfRequested(tester, fixture, 'feedback-export-complete-zh');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Feedback export expiry after a held effect stops later effects and notice',
    (tester) async {
      final effects = _FakeFeedbackExportEffects();
      final held = effects.holdNext('write');
      final fixture = await _mountFeedback(
        tester,
        width: 1280,
        exportEffects: effects,
      );
      await _tapEnabledButton(tester, _feedbackExportButton('导出筛选结果'));
      await held.$1.future;
      expect(effects.calls, ['temporaryDirectory', 'allocate', 'write']);

      final tabs = tester.widget<TabBar>(find.byType(TabBar).first).controller!;
      tabs.index = 8;
      tabs.index = 7;
      await tester.pumpAndSettle();
      held.$2.complete();
      await tester.pumpAndSettle();

      expect(effects.calls, [
        'temporaryDirectory',
        'allocate',
        'write',
        'cleanup',
      ]);
      expect(effects.sharedFiles, isEmpty);
      expect(effects.cleanedFiles, [effects.allocatedFiles.single]);
      expect(find.textContaining('反馈 CSV 已导出'), findsNothing);
      expect(fixture.exportReads, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Feedback empty, error, and loading states follow locale', (
    tester,
  ) async {
    final empty = await _mountFeedback(tester, items: const []);
    expect(find.text('暂无反馈'), findsOneWidget);
    I18n.setLocale(AppLocale.en);
    await tester.pumpAndSettle();
    expect(find.text('No feedback yet.'), findsOneWidget);
    expect(empty.feedbackReads, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    empty.dispose();

    I18n.setLocale(AppLocale.zh);
    final failed = await _mountFeedback(tester);
    failed.failNextPageReads = 1;
    await _tapEnabledButton(tester, _feedbackRefreshButton());
    expect(_feedbackRetryButton(), findsOneWidget);
    await _captureIfRequested(tester, failed, 'feedback-page-error-zh');
    I18n.setLocale(AppLocale.en);
    await tester.pumpAndSettle();
    expect(_feedbackRetryButton(), findsOneWidget);
    expect(failed.feedbackReads, hasLength(2));
    await tester.pumpWidget(const SizedBox.shrink());
    failed.dispose();

    I18n.setLocale(AppLocale.zh);
    final loading = await _mountFeedback(tester, holdInitialRead: true);
    expect(find.text('正在加载反馈列表…'), findsOneWidget);
    I18n.setLocale(AppLocale.en);
    await tester.pump();
    expect(find.text('Loading feedback…'), findsOneWidget);
    loading.initialHeldPageRead!.$2.complete(
      _pageResponse(
        loading.items.take(20).toList(),
        total: loading.items.length,
        limit: 20,
        offset: 0,
      ),
    );
    await tester.pumpAndSettle();
    await _scrollFeedbackUntilHitTestable(tester, _feedbackCard(7));
    expect(find.text('literal feedback 原文 7'), findsOneWidget);
    expect(loading.feedbackReads, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Feedback cards fill the same list width for empty and long text',
    (tester) async {
      final fixture = await _mountFeedback(
        tester,
        width: 1280,
        items: [
          _feedbackItem(1, content: ''),
          _feedbackItem(2, content: '短文'),
          _feedbackItem(3, content: '长文本 long feedback ' * 30),
        ],
      );
      for (final id in [1, 2, 3]) {
        final card = find.descendant(
          of: _feedbackCard(id),
          matching: find.byType(AppSurfaceCard),
        );
        expect(card, findsOneWidget);
        expect(tester.getSize(card).width, closeTo(1264, 0.5));
      }
      await _captureIfRequested(
        tester,
        fixture,
        'feedback-desktop-card-widths',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Feedback IME show and hide preserves draft and expired close geometry',
    (tester) async {
      final fixture = await _mountFeedback(tester, height: 720, textScale: 1.4);
      await _openFeedbackAction(
        tester,
        7,
        icon: Icons.reply_outlined,
        tooltip: '回复',
      );
      final reply = find.byKey(const ValueKey('admin_feedback_reply_dialog'));
      final originalElement = tester.element(reply);
      const draft = '显示隐藏键盘后保留的回复 IME draft';
      await tester.enterText(_replyField(), draft);
      final staleSave = tester
          .widget<FilledButton>(_replySubmitButton(reply))
          .onPressed!;
      for (final inset in [280.0, 0.0, 280.0]) {
        tester.view.viewInsets = FakeViewPadding(bottom: inset);
        fixture.keyboardInset.value = inset;
        await tester.pumpAndSettle();
        expect(tester.element(reply), same(originalElement));
        expect(tester.widget<TextField>(_replyField()).controller!.text, draft);
        _expectDialogAboveKeyboard(tester, reply, 720 - inset);
        _expectAboveKeyboard(tester, _replySubmitButton(reply), 720 - inset);
        final cancel = find.descendant(
          of: reply,
          matching: find.widgetWithText(TextButton, '取消'),
        );
        _expectAboveKeyboard(tester, cancel, 720 - inset);
      }
      fixture.auth.replacePermissions(const ['__none__']);
      fixture.auth.replacePermissions(const ['feedback']);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('操作已失效'), findsOneWidget);
      expect(_replyField(), findsNothing);
      _expectDialogAboveKeyboard(tester, find.byType(AlertDialog), 440);
      final close = find.widgetWithText(TextButton, '关闭').hitTestable();
      _expectAboveKeyboard(tester, close, 440);
      await _captureIfRequested(tester, fixture, 'feedback-ime-phone-expired');
      staleSave();
      await tester.pump();
      expect(fixture.feedbackWrites, isEmpty);
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(fixture.feedbackWrites, isEmpty);
      expect(fixture.feedbackReads, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );

  for (final layout in const [
    (
      width: 320.0,
      height: 720.0,
      textScale: 1.6,
      inset: 0.0,
      dark: false,
      name: 'phone-320-1_6',
    ),
    (
      width: 320.0,
      height: 720.0,
      textScale: 2.0,
      inset: 0.0,
      dark: false,
      name: 'phone-320-2_0',
    ),
    (
      width: 390.0,
      height: 540.0,
      textScale: 1.6,
      inset: 0.0,
      dark: false,
      name: 'short-phone-1_6',
    ),
    (
      width: 390.0,
      height: 720.0,
      textScale: 1.4,
      inset: 280.0,
      dark: false,
      name: 'ime-phone',
    ),
    (
      width: 1280.0,
      height: 900.0,
      textScale: 1.0,
      inset: 0.0,
      dark: true,
      name: 'dark-desktop',
    ),
  ]) {
    testWidgets('Feedback list and dialogs remain reachable: ${layout.name}', (
      tester,
    ) async {
      final fixture = await _mountFeedback(
        tester,
        width: layout.width,
        height: layout.height,
        textScale: layout.textScale,
        viewInsetsBottom: layout.inset,
        dark: layout.dark,
        items: [
          _feedbackItem(
            7,
            username:
                'long-user-name-for-narrow-feedback-layout@example.invalid',
            displayName: '长文本反馈用户 long display name 原文',
            email:
                'long-unbroken-feedback-address-abcdefghijklmnopqrstuvwxyz@example.invalid',
            content: '低高度与放大文字下仍要可读的反馈正文：通知没有声音，而且系统重复弹出了两条提醒。',
            adminReply: '这是很长的已有管理员回复，用于检查回复预览和编辑框的窄屏换行与滚动。',
          ),
        ],
      );
      await _captureIfRequested(
        tester,
        fixture,
        'feedback-${layout.name}-list',
      );
      expect(_feedbackSearch(), findsOneWidget);
      expect(_feedbackSearch().hitTestable(), findsOneWidget);
      await _openFeedbackAction(
        tester,
        7,
        icon: Icons.visibility_outlined,
        tooltip: '查看反馈详情',
      );
      final detail = find.byKey(const ValueKey('admin_feedback_detail_dialog'));
      expect(detail, findsOneWidget);
      _expectDialogAboveKeyboard(tester, detail, layout.height - layout.inset);
      await _captureIfRequested(
        tester,
        fixture,
        'feedback-${layout.name}-detail',
      );
      final detailClose = find.descendant(
        of: detail,
        matching: find.widgetWithText(TextButton, '关闭'),
      );
      await tester.ensureVisible(detailClose);
      expect(detailClose.hitTestable(), findsOneWidget);
      _expectAboveKeyboard(tester, detailClose, layout.height - layout.inset);
      await _tapEnabledButton(tester, detailClose);

      await _openFeedbackAction(
        tester,
        7,
        icon: Icons.reply_outlined,
        tooltip: '回复',
      );
      final reply = find.byKey(const ValueKey('admin_feedback_reply_dialog'));
      await tester.ensureVisible(_replyField());
      expect(_replyField().hitTestable(), findsOneWidget);
      expect(_replySubmitButton(reply).hitTestable(), findsOneWidget);
      _expectDialogAboveKeyboard(tester, reply, layout.height - layout.inset);
      _expectAboveKeyboard(
        tester,
        _replySubmitButton(reply),
        layout.height - layout.inset,
      );
      await _captureIfRequested(
        tester,
        fixture,
        'feedback-${layout.name}-reply',
      );
      if (layout.inset > 0) {
        const draft = '键盘显示时保留的回复草稿 IME draft';
        await tester.enterText(_replyField(), draft);
        await tester.ensureVisible(_replyStatusControl());
        await _tapHitTestableWidget(
          tester,
          _replyStatusControl(),
          (widget) => widget is InkWell && widget.onTap != null,
        );
        final picker = find.byKey(const ValueKey('admin_feedback_picker'));
        _expectDialogAboveKeyboard(
          tester,
          picker,
          layout.height - layout.inset,
        );
        final pickerCancel = find.descendant(
          of: picker,
          matching: find.widgetWithText(TextButton, '取消'),
        );
        _expectAboveKeyboard(
          tester,
          pickerCancel,
          layout.height - layout.inset,
        );
        await _captureIfRequested(tester, fixture, 'feedback-ime-phone-picker');
        final inProgress = find.descendant(
          of: picker,
          matching: find.widgetWithText(ListTile, '处理中'),
        );
        await tester.ensureVisible(inProgress);
        await _tapHitTestableWidget(
          tester,
          inProgress,
          (widget) => widget is ListTile && widget.onTap != null,
        );
        expect(tester.widget<TextField>(_replyField()).controller!.text, draft);
        expect(
          find.descendant(
            of: _replyStatusControl(),
            matching: find.text('处理中'),
          ),
          findsOneWidget,
        );
        await tester.ensureVisible(_replyStatusControl());
        await _tapHitTestableWidget(
          tester,
          _replyStatusControl(),
          (widget) => widget is InkWell && widget.onTap != null,
        );
        await _tapDialogButton(
          tester,
          picker,
          find.widgetWithText(TextButton, '取消'),
        );
        expect(tester.widget<TextField>(_replyField()).controller!.text, draft);
        _expectDialogAboveKeyboard(tester, reply, layout.height - layout.inset);
      }
      await _tapDialogButton(
        tester,
        reply,
        find.widgetWithText(TextButton, '取消'),
      );

      await _openFeedbackAction(
        tester,
        7,
        icon: Icons.inventory_2_outlined,
        tooltip: '关闭',
      );
      expect(find.text('关闭反馈？'), findsOneWidget);
      final confirm = find.widgetWithText(FilledButton, '关闭');
      await tester.ensureVisible(confirm);
      expect(confirm.hitTestable(), findsOneWidget);
      _expectDialogAboveKeyboard(
        tester,
        find.byType(AlertDialog),
        layout.height - layout.inset,
      );
      _expectAboveKeyboard(tester, confirm, layout.height - layout.inset);
      await _captureIfRequested(
        tester,
        fixture,
        'feedback-${layout.name}-confirm',
      );
      await _tapEnabledButton(tester, find.widgetWithText(TextButton, '取消'));
      expect(fixture.feedbackWrites, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}

void _expectAboveKeyboard(
  WidgetTester tester,
  Finder finder,
  double keyboardTop,
) {
  final rect = tester.getRect(finder);
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(rect.bottom, lessThanOrEqualTo(keyboardTop + 0.5));
}

void _expectDialogAboveKeyboard(
  WidgetTester tester,
  Finder modal,
  double keyboardTop,
) {
  final surface = find
      .descendant(
        of: modal,
        matching: find.byWidgetPredicate(
          (widget) => widget is Material && widget.type == MaterialType.card,
        ),
      )
      .first;
  expect(surface, findsOneWidget);
  _expectAboveKeyboard(tester, surface, keyboardTop);
}

Finder _feedbackModule() => find.byKey(const ValueKey('admin-feedback-0'));
Finder _feedbackSearch() => find.byKey(const ValueKey('admin_feedback_search'));
Finder _feedbackScroll() => find.byKey(const ValueKey('admin_feedback_scroll'));
Finder _feedbackPagination() =>
    find.byKey(const ValueKey('admin_feedback_pagination'));
Finder _replyField() =>
    find.byKey(const ValueKey('admin_feedback_reply_field'));
Finder _replyStatusControl() =>
    find.byKey(const ValueKey('admin_feedback_reply_status'));

Finder _feedbackCard(int id) =>
    find.byKey(ValueKey('admin_feedback_swipe_$id'));

Finder _feedbackRefreshButton() => find.descendant(
  of: _feedbackModule(),
  matching: find.widgetWithIcon(TextButton, Icons.refresh),
);

Finder _feedbackRetryButton() => find.descendant(
  of: _feedbackModule(),
  matching: find.widgetWithIcon(OutlinedButton, Icons.refresh),
);

Finder _feedbackExportButton(String tooltip) => find.descendant(
  of: _feedbackModule(),
  matching: find.byWidgetPredicate(
    (widget) => widget is IconButton && widget.tooltip == tooltip,
  ),
);

Finder _nextFeedbackPage() => find.descendant(
  of: _feedbackPagination(),
  matching: find.widgetWithIcon(IconButton, Icons.chevron_right),
);

Finder _pageSizeButton(int size, [String locale = 'zh']) => find.descendant(
  of: _feedbackPagination(),
  matching: find.widgetWithText(
    TextButton,
    '${locale == 'zh' ? '每页' : 'Per page'}: $size',
  ),
);

String _sortControlValue(WidgetTester tester) =>
    (tester
                .widget<InputDecorator>(
                  find.descendant(
                    of: find.byKey(const ValueKey('admin_feedback_sort')),
                    matching: find.byType(InputDecorator),
                  ),
                )
                .child
            as Text)
        .data!;

ScrollableState _feedbackScrollState(WidgetTester tester) {
  final scrollable = find.descendant(
    of: _feedbackScroll(),
    matching: find.byType(Scrollable),
  );
  return tester.state<ScrollableState>(scrollable.first);
}

Future<void> _tapChoiceChip(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expect(finder, findsOneWidget);
  expect(finder.hitTestable(), findsOneWidget);
  expect(tester.widget<ChoiceChip>(finder).onSelected, isNotNull);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _openFeedbackSort(WidgetTester tester, String optionText) async {
  final control = find.byKey(const ValueKey('admin_feedback_sort'));
  await _tapHitTestableWidget(
    tester,
    control,
    (widget) => widget is InkWell && widget.onTap != null,
  );
  final picker = find.byKey(const ValueKey('admin_feedback_picker'));
  await _tapPickerOption(tester, picker, optionText);
}

Future<void> _openPageSize(WidgetTester tester, int size) async {
  await _returnToFeedbackFooter(tester, target: _pageSizeButton(20));
  await _tapEnabledButton(tester, _pageSizeButton(20));
  final picker = find.byKey(const ValueKey('admin_feedback_picker'));
  await _tapPickerOption(tester, picker, '$size');
}

Future<void> _tapPickerOption(
  WidgetTester tester,
  Finder picker,
  String option,
) async {
  final optionText = find.descendant(of: picker, matching: find.text(option));
  expect(optionText, findsOneWidget);
  final tile = find.ancestor(of: optionText, matching: find.byType(ListTile));
  await tester.ensureVisible(tile);
  await tester.pumpAndSettle();
  expect(tile.hitTestable(), findsOneWidget);
  await tester.tap(tile);
  await tester.pumpAndSettle();
}

Future<void> _openFeedbackAction(
  WidgetTester tester,
  int id, {
  required IconData icon,
  required String tooltip,
}) async {
  final card = _feedbackCard(id);
  await _scrollFeedbackUntilHitTestable(tester, card);
  await tester.ensureVisible(card);
  await tester.pumpAndSettle();
  expect(card, findsOneWidget);
  if (find
      .descendant(of: card, matching: find.byTooltip(tooltip))
      .evaluate()
      .isEmpty) {
    await tester.drag(card, const Offset(-220, 0));
    await tester.pumpAndSettle();
  }
  final iconFinder = find.descendant(of: card, matching: find.byIcon(icon));
  final target = find.ancestor(of: iconFinder, matching: find.byType(InkWell));
  expect(target, findsOneWidget);
  expect(target.hitTestable(), findsOneWidget);
  expect(
    find.descendant(of: card, matching: find.byTooltip(tooltip)),
    findsOneWidget,
  );
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _tapDialogButton(
  WidgetTester tester,
  Finder dialog,
  Finder button,
) async {
  final scoped = find.descendant(of: dialog, matching: button);
  await tester.ensureVisible(scoped);
  await tester.pumpAndSettle();
  expect(scoped, findsOneWidget);
  expect(scoped.hitTestable(), findsOneWidget);
  await tester.tap(scoped);
  await tester.pumpAndSettle();
}

Finder _replySubmitButton(Finder dialog) => find.descendant(
  of: dialog,
  matching: find.widgetWithText(FilledButton, '提交'),
);

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
    FilledButton value => value.onPressed,
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

Future<void> _scrollFeedbackUntilHitTestable(
  WidgetTester tester,
  Finder target, {
  double delta = 220,
}) async {
  final scrollable = find
      .descendant(of: _feedbackScroll(), matching: find.byType(Scrollable))
      .first;
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

Future<void> _returnToFeedbackTop(WidgetTester tester, {Finder? target}) async {
  _feedbackScrollState(tester).position.jumpTo(0);
  await tester.pumpAndSettle();
  final finder = target ?? _feedbackSearch();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
}

Future<void> _returnToFeedbackFooter(
  WidgetTester tester, {
  required Finder target,
}) async {
  await _scrollFeedbackUntilHitTestable(tester, target);
}

Future<_FeedbackFixture> _mountFeedback(
  WidgetTester tester, {
  List<String> permissions = const ['feedback'],
  List<Map<String, dynamic>>? items,
  int? total,
  double width = 390,
  double height = 900,
  double textScale = 1,
  double viewInsetsBottom = 0,
  bool dark = false,
  bool holdInitialRead = false,
  _FakeFeedbackExportEffects? exportEffects,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  if (viewInsetsBottom > 0) {
    tester.view.viewInsets = FakeViewPadding(bottom: viewInsetsBottom);
  }
  addTearDown(tester.view.reset);
  await tester.runAsync(loadWidgetPolishScreenshotFonts);
  final fixture = _FeedbackFixture(permissions: permissions)
    ..items = items ?? List.generate(45, (index) => _feedbackItem(index + 1))
    ..total = total
    ..keyboardInset.value = viewInsetsBottom;
  if (holdInitialRead) {
    fixture.initialHeldPageRead = fixture.holdNextPageRead();
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
          child: ValueListenableBuilder<double>(
            valueListenable: fixture.keyboardInset,
            child: child,
            builder: (context, inset, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(textScale),
                viewInsets: EdgeInsets.only(bottom: inset),
              ),
              child: child!,
            ),
          ),
        ),
        home: AdminScreen(
          initialTabIndex: 7,
          feedbackExportEffects:
              exportEffects ?? const PlatformAdminFeedbackExportEffects(),
        ),
      ),
    ),
  );
  if (holdInitialRead) {
    await tester.pump();
    await fixture.initialHeldPageRead!.$1.future;
  } else {
    await tester.pumpAndSettle();
  }
  final feedbackAllowed =
      permissions.contains('feedback') && !permissions.contains('__none__');
  if (feedbackAllowed) {
    expect(_feedbackModule(), findsOneWidget);
    if (holdInitialRead) {
      expect(find.text('正在加载反馈列表…'), findsOneWidget);
    } else {
      expect(fixture.feedbackReads, hasLength(1));
    }
  } else {
    expect(_feedbackModule(), findsNothing);
    expect(fixture.feedbackReads, isEmpty);
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
  _FeedbackFixture fixture,
  String name,
) async {
  final directoryPath =
      Platform.environment['DUOYI_ADMIN_FEEDBACK_SCREENSHOT_DIR'];
  if (directoryPath == null || directoryPath.trim().isEmpty) return;
  final requiredRoot = Directory(
    'evidence/screenshots/admin-feedback-locale-origin-20261015',
  ).absolute.path;
  final outputDirectory = Directory(directoryPath).absolute.path;
  if (outputDirectory != requiredRoot &&
      !outputDirectory.startsWith('$requiredRoot${Platform.pathSeparator}')) {
    throw StateError(
      'DUOYI_ADMIN_FEEDBACK_SCREENSHOT_DIR must stay under evidence/screenshots/admin-feedback-locale-origin-20261015/.',
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

class _FeedbackFixture {
  _FeedbackFixture({required List<String> permissions}) {
    items = List.generate(45, (index) => _feedbackItem(index + 1));
    final initialClient = newClient(token: 'synthetic-feedback-token');
    auth = _FeedbackAuth(
      client: initialClient,
      state: _adminState(permissions: permissions),
    );
  }

  final List<_CapturedFeedbackRequest> requests = [];
  final List<http.Client> transports = [];
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();
  final AppAccessRouteGate routeGate = AppAccessRouteGate();
  final GlobalKey screenshotKey = GlobalKey();
  final keyboardInset = ValueNotifier<double>(0);
  late List<Map<String, dynamic>> items;
  int? total;
  late final _FeedbackAuth auth;
  (Completer<void>, Completer<http.Response>)? initialHeldPageRead;
  (Completer<void>, Completer<http.Response>)? _nextPageRead;
  (Completer<void>, Completer<http.Response>)? _nextDetailRead;
  int? _nextDetailId;
  (Completer<void>, Completer<http.Response>)? _nextWrite;
  int failNextPageReads = 0;
  bool _disposed = false;

  List<_CapturedFeedbackRequest> get feedbackReads => requests
      .where(
        (request) => request.method == 'GET' && request.path == _feedbackPath,
      )
      .toList();
  List<_CapturedFeedbackRequest> get detailReads => requests
      .where(
        (request) =>
            request.method == 'GET' &&
            request.path.startsWith('$_feedbackPath/'),
      )
      .toList();
  List<_CapturedFeedbackRequest> get exportReads => requests
      .where(
        (request) =>
            request.method == 'GET' &&
            request.path == '$_feedbackPath/export.csv',
      )
      .toList();
  List<_CapturedFeedbackRequest> get feedbackWrites => requests
      .where(
        (request) =>
            request.method != 'GET' && request.path.startsWith(_feedbackPath),
      )
      .toList();
  List<String> get requestLines =>
      requests.map((request) => request.line).toList();

  ApiClient newClient({
    required String token,
    String baseUrl = 'https://duoyi.test',
  }) {
    final transport = MockClient(_handle);
    transports.add(transport);
    return ApiClient(baseUrl: baseUrl, token: token, httpClient: transport);
  }

  (Completer<void>, Completer<http.Response>) holdNextPageRead() {
    final held = (Completer<void>(), Completer<http.Response>());
    _nextPageRead = held;
    return held;
  }

  (Completer<void>, Completer<http.Response>) holdNextDetailRead(int id) {
    final held = (Completer<void>(), Completer<http.Response>());
    _nextDetailId = id;
    _nextDetailRead = held;
    return held;
  }

  (Completer<void>, Completer<http.Response>) holdNextWrite() {
    final held = (Completer<void>(), Completer<http.Response>());
    _nextWrite = held;
    return held;
  }

  void _applyFeedbackWrite(http.Request request) {
    if (request.method != 'DELETE') return;
    final id = int.tryParse(request.url.path.split('/').last);
    if (id == null) return;
    final oldLength = items.length;
    items.removeWhere((item) => item['id'] == id);
    final removed = oldLength - items.length;
    if (removed > 0 && total != null) total = total! - removed;
  }

  Future<http.Response> _handle(http.Request request) async {
    requests.add(
      _CapturedFeedbackRequest(
        method: request.method,
        path: request.url.path,
        query: request.url.query,
        queryParameters: Map<String, String>.of(request.url.queryParameters),
        authorization: request.headers['authorization'] ?? '',
        host: request.url.host,
        body: request.body,
      ),
    );
    if (request.method == 'GET' && request.url.path == _feedbackPath) {
      final held = _nextPageRead;
      _nextPageRead = null;
      if (held != null) {
        held.$1.complete();
        return held.$2.future;
      }
      if (failNextPageReads > 0) {
        failNextPageReads--;
        return _json({'detail': 'literal feedback failure'}, 500);
      }
      final limit =
          int.tryParse(request.url.queryParameters['limit'] ?? '') ?? 20;
      final offset =
          int.tryParse(request.url.queryParameters['offset'] ?? '') ?? 0;
      final page = items.skip(offset).take(limit).toList();
      final pageTotal = total ?? items.length;
      return _json({
        'items': page,
        'total': pageTotal,
        'limit': limit,
        'offset': offset,
        'has_more': offset + page.length < pageTotal,
      });
    }
    if (request.method == 'GET' &&
        request.url.path == '$_feedbackPath/export.csv') {
      return http.Response.bytes(
        utf8.encode('\uFEFFid,title\n7,literal feedback 原文 7\n'),
        200,
        headers: const {'content-type': 'text/csv'},
      );
    }
    if (request.method == 'GET' &&
        request.url.path.startsWith('$_feedbackPath/')) {
      final id = int.tryParse(request.url.path.split('/').last) ?? 0;
      final held = _nextDetailRead;
      if (held != null && _nextDetailId == id) {
        _nextDetailRead = null;
        _nextDetailId = null;
        held.$1.complete();
        return held.$2.future;
      }
      final matches = items.where((item) => item['id'] == id).toList();
      return _json(matches.isEmpty ? <String, dynamic>{} : matches.first);
    }
    if (request.method != 'GET' && request.url.path.startsWith(_feedbackPath)) {
      final held = _nextWrite;
      _nextWrite = null;
      if (held != null) {
        held.$1.complete();
        final response = await held.$2.future;
        _applyFeedbackWrite(request);
        return response;
      }
      _applyFeedbackWrite(request);
      return _json({'status': 'ok'});
    }
    if (request.method == 'GET' && request.url.path == '/api/config') {
      return _json({});
    }
    return _json({'detail': 'Not Found'}, 404);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    auth.dispose();
    for (final transport in transports) {
      transport.close();
    }
    routeGate.dispose();
    keyboardInset.dispose();
  }
}

class _FeedbackAuth extends AuthProvider {
  _FeedbackAuth({required ApiClient client, required AuthState state})
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

  void replacePermissionsWithoutNotify(List<String> permissions) {
    _currentState = _currentState.copyWith(adminPermissions: permissions);
  }

  void changeAuthorityWithoutNotify({String? clientToken, String? baseUrl}) {
    if (clientToken != null) _currentClient.token = clientToken;
    if (baseUrl != null) _currentClient.baseUrl = baseUrl;
  }

  void replaceClientSilently(ApiClient client, {required String token}) {
    _currentClient = client;
    _currentState = _currentState.copyWith(token: token);
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

class _FakeFeedbackExportEffects implements AdminFeedbackExportEffects {
  final List<String> calls = [];
  final List<AdminFeedbackExportFile> allocatedFiles = [];
  final List<String> writtenCsv = [];
  final List<String> copiedPaths = [];
  final List<AdminFeedbackExportFile> sharedFiles = [];
  final List<String> sharedTexts = [];
  final List<String> sharedSubjects = [];
  final List<AdminFeedbackExportFile> cleanedFiles = [];
  String? _heldStage;
  Completer<void>? _started;
  Completer<void>? _release;
  int _fileNumber = 0;

  (Completer<void>, Completer<void>) holdNext(String stage) {
    _heldStage = stage;
    _started = Completer<void>();
    _release = Completer<void>();
    return (_started!, _release!);
  }

  Future<void> _hold(String stage) async {
    if (_heldStage != stage) return;
    if (!_started!.isCompleted) _started!.complete();
    await _release!.future;
  }

  @override
  Future<String> temporaryDirectory() async {
    calls.add('temporaryDirectory');
    await _hold('temporaryDirectory');
    return '/temporary';
  }

  @override
  Future<AdminFeedbackExportFile> allocate(String temporaryDirectory) async {
    calls.add('allocate');
    await _hold('allocate');
    final id = ++_fileNumber;
    final directory = '$temporaryDirectory/feedback_export_$id';
    final file = AdminFeedbackExportFile(
      directory: directory,
      path: '$directory/duoyi_feedback_$id.csv',
    );
    allocatedFiles.add(file);
    return file;
  }

  @override
  Future<void> write(AdminFeedbackExportFile file, String csv) async {
    calls.add('write');
    writtenCsv.add(csv);
    await _hold('write');
  }

  @override
  Future<void> copyPath(String path) async {
    calls.add('copyPath');
    copiedPaths.add(path);
    await _hold('copyPath');
  }

  @override
  Future<void> share(
    AdminFeedbackExportFile file,
    String text,
    String subject,
  ) async {
    calls.add('share');
    sharedFiles.add(file);
    sharedTexts.add(text);
    sharedSubjects.add(subject);
    await _hold('share');
  }

  @override
  Future<void> cleanup(AdminFeedbackExportFile file) async {
    calls.add('cleanup');
    cleanedFiles.add(file);
  }
}

Map<String, dynamic> _feedbackItem(
  int id, {
  String? username,
  String? displayName,
  String? email,
  Object? emailVerified = true,
  String category = 'bug',
  String status = 'open',
  String? content,
  String? adminReply,
}) => {
  'id': id,
  'username': username ?? 'literal-user-$id',
  'display_name': displayName ?? 'literal display 原文 $id',
  'email': email ?? 'feedback-$id@example.invalid',
  'email_verified': emailVerified,
  'category': category,
  'content': content ?? 'literal feedback 原文 $id',
  'status': status,
  'admin_reply': adminReply ?? '',
  'created_at': '2026-10-15 08:15:00',
  'updated_at': '2026-10-15 09:20:00',
};

AuthState _adminState({required List<String> permissions}) => AuthState(
  userId: _selfId,
  username: 'literal-feedback-admin',
  token: 'synthetic-feedback-token',
  isAdmin: true,
  adminPermissions: permissions,
);

http.Response _pageResponse(
  List<Map<String, dynamic>> items, {
  required int total,
  required int limit,
  required int offset,
}) => _json({
  'items': items,
  'total': total,
  'limit': limit,
  'offset': offset,
  'has_more': offset + items.length < total,
});

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);

class _CapturedFeedbackRequest {
  const _CapturedFeedbackRequest({
    required this.method,
    required this.path,
    required this.query,
    required this.queryParameters,
    required this.authorization,
    required this.host,
    required this.body,
  });

  final String method;
  final String path;
  final String query;
  final Map<String, String> queryParameters;
  final String authorization;
  final String host;
  final String body;

  String get line => '$method $path${query.isEmpty ? '' : '?$query'}';
}
