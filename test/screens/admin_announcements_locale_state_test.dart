import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

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

const _announcementId = 1042;
const _createdId = _announcementId + 1;
const _announcementTitle = 'Literal announcement 标题 A';
const _announcementBody = 'Literal announcement body 原文 A';
const _draftTitle = 'literal draft 保留';
const _draftBody = 'literal body draft 保留';
const _createdTitle = 'Created announcement 原文';
const _createdBody = 'Created body 原文';
const _editedTitle = 'Edited announcement 原文';
const _editedBody = 'Edited body 原文';
final _cjk = RegExp(r'[\u3400-\u9fff]');

void main() {
  setUp(() => I18n.setLocale(AppLocale.zh));
  tearDown(() => I18n.setLocale(AppLocale.zh));

  testWidgets(
    'Announcements zh-en-zh keeps the list, scroll state, draft, selection, focus, and dialog route',
    (tester) async {
      final fixture = await _mountAnnouncements(tester);
      final module = find.byKey(const ValueKey('admin-announcements-0'));
      expect(module, findsOneWidget);
      final moduleElement = tester.element(module);
      final title = find.descendant(
        of: module,
        matching: find.text(_announcementTitle),
      );
      expect(title, findsOneWidget);
      final titleElement = tester.element(title);
      final scrollableElements = _scrollableElements(tester, module);
      expect(scrollableElements, isNotEmpty);
      final scrollIndex = _scrollableIndexWithContent(
        tester,
        scrollableElements,
      );
      final scrollableElement = scrollableElements[scrollIndex];
      final scrollableState = tester.state<ScrollableState>(
        _elementFinder(scrollableElement),
      );
      if (scrollableState.position.maxScrollExtent > 60) {
        scrollableState.position.jumpTo(60);
        await tester.pumpAndSettle();
      }
      await _openEditDialog(tester);
      // Opening the real row menu first brings its anchor into view.
      final scrollOffset = scrollableState.position.pixels;
      final dialogRoute = fixture.routes.current;
      expect(dialogRoute, isNotNull);
      expect(find.byType(Dialog), findsOneWidget);
      final titleField = _dialogFields(tester).first;
      await tester.enterText(titleField, _draftTitle);
      final controller = tester.widget<TextField>(titleField).controller!;
      controller.selection = const TextSelection(
        baseOffset: 1,
        extentOffset: 9,
      );
      final selection = controller.selection;
      final focusNode = tester
          .widget<EditableText>(
            find.descendant(
              of: titleField,
              matching: find.byType(EditableText),
            ),
          )
          .focusNode;
      expect(FocusManager.instance.primaryFocus, same(focusNode));
      final readsBeforeLocaleChanges = List<String>.of(fixture.requestLines);
      final pushesBeforeLocaleChanges = fixture.routes.pushed.length;

      for (final locale in [AppLocale.en, AppLocale.zh]) {
        I18n.setLocale(locale);
        await tester.pumpAndSettle();
        expect(tester.element(module), same(moduleElement));
        expect(tester.element(title), same(titleElement));
        expect(
          tester.state<ScrollableState>(_elementFinder(scrollableElement)),
          same(scrollableState),
        );
        expect(scrollableState.position.pixels, scrollOffset);
        expect(fixture.routes.current, same(dialogRoute));
        expect(fixture.routes.pushed, hasLength(pushesBeforeLocaleChanges));
        expect(controller.text, _draftTitle);
        expect(controller.selection, selection);
        expect(
          tester.widget<TextField>(_dialogFields(tester).first).controller,
          same(controller),
        );
        expect(FocusManager.instance.primaryFocus, same(focusNode));
        expect(fixture.requestLines, readsBeforeLocaleChanges);
        _expectEditorCopy(
          tester,
          locale,
          editing: true,
          selectedLevel: locale == AppLocale.zh ? '重要' : 'Important',
        );
        if (locale == AppLocale.en) {
          await _captureIfRequested(
            tester,
            fixture,
            'announcements-locale-390-en-edit-form',
          );
        }
        expect(tester.takeException(), isNull);
      }

      await _captureIfRequested(
        tester,
        fixture,
        'announcements-locale-390-zh-edit-form',
      );
      fixture.navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(fixture.requestLines, readsBeforeLocaleChanges);
    },
  );

  testWidgets(
    'open announcement action and level menus follow live locale without replacing routes',
    (tester) async {
      final fixture = await _mountAnnouncements(tester);
      await _revealAnnouncementCard(tester);
      await tester.ensureVisible(_rowMenuButton());
      await tester.tap(_rowMenuButton());
      await tester.pumpAndSettle();
      final menuRoute = fixture.routes.current;
      final pushesBeforeLocale = fixture.routes.pushed.length;
      expect(find.text('编辑'), findsOneWidget);
      expect(find.text('下架'), findsOneWidget);

      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      expect(fixture.routes.current, same(menuRoute));
      expect(fixture.routes.pushed, hasLength(pushesBeforeLocale));
      for (final label in ['Edit', 'Unpublish', 'Delete']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('编辑'), findsNothing);
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      _expectEditorCopy(
        tester,
        AppLocale.en,
        editing: true,
        selectedLevel: 'Important',
      );

      final fields = _dialogFields(tester);
      await tester.enterText(fields[0], _draftTitle);
      await tester.enterText(fields[1], _draftBody);
      final titleController = tester.widget<TextField>(fields[0]).controller;
      final dialogRoute = fixture.routes.current;
      final level = find.descendant(
        of: find.byType(Dialog),
        matching: find.text('Important'),
      );
      await tester.tap(level);
      await tester.pumpAndSettle();
      final levelRoute = fixture.routes.current;
      final pushesBeforeLevelLocale = fixture.routes.pushed.length;
      I18n.setLocale(AppLocale.zh);
      await tester.pumpAndSettle();
      expect(fixture.routes.current, same(levelRoute));
      expect(fixture.routes.pushed, hasLength(pushesBeforeLevelLocale));
      for (final label in ['普通', '重要', '紧急']) {
        expect(find.text(label), findsWidgets);
      }
      expect(find.text('Urgent'), findsNothing);
      await tester.tap(find.text('紧急').last);
      await tester.pumpAndSettle();
      expect(fixture.routes.current, same(dialogRoute));
      expect(
        tester.widget<TextField>(_dialogFields(tester)[0]).controller,
        same(titleController),
      );
      expect(titleController!.text, _draftTitle);
      _expectEditorCopy(
        tester,
        AppLocale.zh,
        editing: true,
        selectedLevel: '紧急',
      );
      expect(fixture.announcementMutations, isEmpty);
      expect(tester.takeException(), isNull);
      await _closeDialog(tester, fixture);
    },
  );

  testWidgets(
    'cancelled announcement editors and confirmations cannot affect reopened dialogs',
    (tester) async {
      final fixture = await _mountAnnouncements(tester);
      final openNew = _newAnnouncementCallback(tester);
      openNew();
      openNew();
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      final fields = _dialogFields(tester);
      await tester.enterText(fields[0], _draftTitle);
      await tester.enterText(fields[1], _draftBody);
      final cancelledTitleController = tester
          .widget<TextField>(fields[0])
          .controller!;
      final cancelledBodyController = tester
          .widget<TextField>(fields[1])
          .controller!;
      final staleSave = _primaryDialogCallback(tester);
      final cancel = find.descendant(
        of: find.byType(Dialog),
        matching: find.widgetWithText(TextButton, '取消'),
      );
      await tester.tap(cancel);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(
        () => cancelledTitleController.addListener(() {}),
        throwsFlutterError,
      );
      expect(
        () => cancelledBodyController.addListener(() {}),
        throwsFlutterError,
      );
      staleSave();
      await tester.pumpAndSettle();
      expect(fixture.announcementMutations, isEmpty);

      await _openNewDialog(tester, AppLocale.zh);
      final newRoute = fixture.routes.current;
      staleSave();
      await tester.pumpAndSettle();
      expect(fixture.routes.current, same(newRoute));
      expect(
        tester.widget<TextField>(_dialogFields(tester)[0]).controller!.text,
        isEmpty,
      );
      await _closeDialog(tester, fixture);

      await _openDeleteDialog(tester);
      final staleDelete = _primaryDialogCallback(tester);
      await _closeDialog(tester, fixture);
      await _openEditDialog(tester);
      final editRoute = fixture.routes.current;
      staleDelete();
      await tester.pumpAndSettle();
      expect(fixture.routes.current, same(editRoute));
      expect(find.byType(Dialog), findsOneWidget);
      expect(fixture.announcementMutations, isEmpty);
      expect(tester.takeException(), isNull);
      await _closeDialog(tester, fixture);
    },
  );

  testWidgets(
    'announcement sort resets on client replacement and rejects an already open stale menu',
    (tester) async {
      final fixture = await _mountAnnouncements(tester);
      await _revealAnnouncementHeader(tester);
      await tester.tap(find.text('最新创建优先'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('标题 A-Z'));
      await tester.pumpAndSettle();
      expect(
        fixture.announcementReads.last.queryParameters['sort'],
        'title_asc',
      );

      fixture.replaceClient(
        fixture.newClient(token: fixture.auth.state.token!),
      );
      await tester.pumpAndSettle();
      expect(
        fixture.announcementReads.last.queryParameters['sort'],
        'created_desc',
      );
      expect(find.text('最新创建优先'), findsOneWidget);
      expect(find.text('标题 A-Z'), findsNothing);

      await tester.tap(find.text('最新创建优先'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('标题 A-Z'));
      await tester.pumpAndSettle();
      final staleSortParentRoute = fixture.routes.current!;
      expect(staleSortParentRoute.isActive, isTrue);
      expect(staleSortParentRoute.isCurrent, isTrue);
      await tester.tap(find.text('标题 A-Z'));
      await tester.pumpAndSettle();
      final staleMenuRoute = fixture.routes.current!;
      expect(staleMenuRoute, isA<PopupRoute<dynamic>>());
      expect(staleMenuRoute.settings.name, 'AppAnchoredDropdownMenu');
      final titleSortRequest = fixture.announcementReads.last;
      expect(titleSortRequest.method, 'GET');
      expect(titleSortRequest.path, '/api/admin/announcements');
      expect(titleSortRequest.body, isEmpty);
      expect(titleSortRequest.queryParameters, <String, String>{
        'sort': 'title_asc',
        'limit': '20',
        'offset': '0',
      });
      expect(
        titleSortRequest.line,
        'GET /api/admin/announcements?sort=title_asc&limit=20&offset=0',
      );
      final requestsBeforeReplacement = List<String>.of(fixture.requestLines);
      final readsBeforeReplacement = List<_CapturedRequest>.of(
        fixture.announcementReads,
      );
      final previousClient = fixture.auth.client;
      final freshClientRequests = <http.Request>[];
      final freshTransport = MockClient((request) {
        freshClientRequests.add(request);
        return fixture._handle(request);
      });
      fixture.transports.add(freshTransport);
      final freshClient = ApiClient(
        baseUrl: previousClient.baseUrl,
        token: fixture.auth.state.token!,
        httpClient: freshTransport,
      );
      expect(freshClient, isNot(same(previousClient)));
      fixture.replaceClient(freshClient);
      expect(fixture.auth.client, same(freshClient));
      tester.view.physicalSize = const Size(360, 900);
      await tester.pumpAndSettle();
      expect(fixture.routes.current, same(staleMenuRoute));
      expect(fixture.requestLines, requestsBeforeReplacement);
      expect(fixture.announcementReads, readsBeforeReplacement);
      expect(freshClientRequests, isEmpty);
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(340, 900);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(fixture.requestLines, requestsBeforeReplacement);
      expect(fixture.announcementReads, readsBeforeReplacement);
      expect(freshClientRequests, isEmpty);
      final requestsBeforeSelection = List<String>.of(fixture.requestLines);
      await tester.tap(find.text('最近更新优先').last);
      await tester.pumpAndSettle();
      expect(fixture.requestLines, requestsBeforeSelection);
      expect(fixture.routes.current, same(staleMenuRoute));
      expect(staleMenuRoute.isActive, isTrue);
      expect(staleMenuRoute.isCurrent, isTrue);
      expect(fixture.requestLines, requestsBeforeReplacement);
      expect(fixture.announcementReads, readsBeforeReplacement);
      expect(fixture.announcementReads.last, same(titleSortRequest));
      expect(freshClientRequests, isEmpty);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('admin-announcements-0')),
          matching: find.text('最新创建优先'),
        ),
        findsOneWidget,
      );
      // Rejection leaves this stale popup open. Dismiss only the captured
      // current popup, without returning a selected value.
      staleMenuRoute.navigator!.pop();
      await tester.pumpAndSettle();
      expect(staleMenuRoute.isActive, isFalse);
      expect(fixture.routes.current, same(staleSortParentRoute));
      expect(staleSortParentRoute.isActive, isTrue);
      expect(staleSortParentRoute.isCurrent, isTrue);
      expect(fixture.requestLines, requestsBeforeSelection);
      expect(fixture.requestLines, requestsBeforeReplacement);
      expect(fixture.announcementReads, readsBeforeReplacement);
      expect(fixture.announcementReads.last, same(titleSortRequest));
      expect(freshClientRequests, isEmpty);
      expect(find.text('最新创建优先'), findsOneWidget);
      expect(find.text('最近更新优先'), findsNothing);
      expect(fixture.announcementMutations, isEmpty);
      expect(tester.takeException(), isNull);

      // A legal choice after parent restoration must use the replacement
      // transport once; no explicit pop assists this successful selection.
      await tester.tap(find.text('最新创建优先'));
      await tester.pumpAndSettle();
      final freshSortMenuRoute = fixture.routes.current!;
      expect(freshSortMenuRoute, isA<PopupRoute<dynamic>>());
      expect(freshSortMenuRoute.settings.name, 'AppAnchoredDropdownMenu');
      expect(freshSortMenuRoute.isActive, isTrue);
      expect(freshSortMenuRoute.isCurrent, isTrue);
      expect(fixture.requestLines, requestsBeforeReplacement);
      expect(freshClientRequests, isEmpty);
      await tester.tap(find.text('最新创建优先').last);
      await tester.pumpAndSettle();
      expect(freshSortMenuRoute.isActive, isFalse);
      expect(fixture.routes.current, same(staleSortParentRoute));
      expect(staleSortParentRoute.isActive, isTrue);
      expect(staleSortParentRoute.isCurrent, isTrue);
      expect(fixture.auth.client, same(freshClient));
      expect(freshClientRequests, hasLength(1));
      final sent = freshClientRequests.single;
      expect(sent.method, 'GET');
      expect(sent.url.path, '/api/admin/announcements');
      expect(sent.body, isEmpty);
      expect(sent.url.queryParameters, <String, String>{
        'sort': 'created_desc',
        'limit': '20',
        'offset': '0',
      });
      final reads = fixture.announcementReads;
      expect(reads, hasLength(readsBeforeReplacement.length + 1));
      expect(
        reads.take(readsBeforeReplacement.length).toList(),
        readsBeforeReplacement,
      );
      final createdSortRequest = reads.last;
      expect(createdSortRequest.method, sent.method);
      expect(createdSortRequest.path, sent.url.path);
      expect(createdSortRequest.body, sent.body);
      expect(createdSortRequest.queryParameters, sent.url.queryParameters);
      expect(
        fixture.requestLines,
        <String>[
          ...requestsBeforeReplacement,
          'GET /api/admin/announcements?sort=created_desc&limit=20&offset=0',
        ],
      );
      expect(fixture.announcementMutations, isEmpty);
      expect(find.text('最新创建优先'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'client replacement in an announcement editor rejects stale level and save then allows a new draft',
    (tester) async {
      final fixture = await _mountAnnouncements(tester);
      await _openEditDialog(tester);
      final staleDialogRoute = fixture.routes.current!;
      expect(staleDialogRoute, isA<DialogRoute<dynamic>>());
      final fields = _dialogFields(tester);
      await tester.enterText(fields[0], _draftTitle);
      await tester.enterText(fields[1], _draftBody);
      final staleSave = _primaryDialogCallback(tester);
      await tester.tap(
        find.descendant(of: find.byType(Dialog), matching: find.text('重要')),
      );
      await tester.pumpAndSettle();
      final staleLevelMenuRoute = fixture.routes.current!;
      expect(staleLevelMenuRoute, isA<PopupRoute<dynamic>>());
      expect(staleLevelMenuRoute.settings.name, 'AppAnchoredDropdownMenu');
      fixture.replaceClient(
        fixture.newClient(token: fixture.auth.state.token!),
      );
      await tester.pumpAndSettle();
      final requestsBeforeSelection = List<String>.of(fixture.requestLines);
      await tester.tap(find.text('紧急').last);
      await tester.pumpAndSettle();
      expect(fixture.routes.current, same(staleLevelMenuRoute));
      expect(staleLevelMenuRoute.isActive, isTrue);
      expect(staleLevelMenuRoute.isCurrent, isTrue);
      expect(fixture.requestLines, requestsBeforeSelection);
      expect(fixture.announcementMutations, isEmpty);
      _expectEditorCopy(
        tester,
        AppLocale.zh,
        editing: true,
        selectedLevel: '重要',
      );
      staleLevelMenuRoute.navigator!.pop();
      await tester.pumpAndSettle();
      expect(staleLevelMenuRoute.isActive, isFalse);
      expect(fixture.routes.current, same(staleDialogRoute));
      expect(staleDialogRoute.isCurrent, isTrue);
      expect(fixture.requestLines, requestsBeforeSelection);
      staleSave();
      await tester.pumpAndSettle();
      expect(fixture.requestLines, requestsBeforeSelection);
      expect(fixture.announcementMutations, isEmpty);
      await tester.tap(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.widgetWithText(TextButton, '取消'),
        ),
      );
      await tester.pumpAndSettle();

      await _openNewDialog(tester, AppLocale.zh);
      final newFields = _dialogFields(tester);
      await tester.enterText(newFields[0], _createdTitle);
      await tester.enterText(newFields[1], _createdBody);
      await _tapDialogPrimary(tester);
      expect(fixture.announcementMutations, hasLength(1));
      expect(fixture.announcementMutations.single.method, 'POST');
      expect(fixture.mutationBodies.single['title'], _createdTitle);
      expect(
        fixture.announcementReads.last.queryParameters['sort'],
        'created_desc',
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final layout in const [
    (scale: 1.6, name: '1_6'),
    (scale: 2.0, name: '2_0'),
  ]) {
    testWidgets(
      'Announcements populated and dialogs fit 320px at text scale ${layout.scale}',
      (tester) async {
        final fixture = await _mountAnnouncements(
          tester,
          width: 320,
          textScale: layout.scale,
        );
        expect(
          find.byKey(const ValueKey('admin-announcements-0')),
          findsOneWidget,
        );
        expect(find.text(_announcementTitle), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _captureIfRequested(
          tester,
          fixture,
          'announcements-320-${layout.name}-zh-populated',
        );

        I18n.setLocale(AppLocale.en);
        await tester.pumpAndSettle();
        expect(find.text(_announcementTitle), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _captureIfRequested(
          tester,
          fixture,
          'announcements-320-${layout.name}-en-populated',
        );

        await _openNewDialog(tester, AppLocale.en);
        _expectEditorCopy(
          tester,
          AppLocale.en,
          editing: false,
          selectedLevel: 'Info',
        );
        await _expectLevelOptions(tester, AppLocale.en);
        expect(tester.takeException(), isNull);
        await _captureIfRequested(
          tester,
          fixture,
          'announcements-320-${layout.name}-en-new-form',
        );
        await _closeDialog(tester, fixture);

        await _openEditDialog(tester);
        _expectEditorCopy(
          tester,
          AppLocale.en,
          editing: true,
          selectedLevel: 'Important',
        );
        expect(tester.takeException(), isNull);
        await _captureIfRequested(
          tester,
          fixture,
          'announcements-320-${layout.name}-en-edit-form',
        );
        await _closeDialog(tester, fixture);

        await _openDeleteDialog(tester);
        _expectDialogLocale(tester, AppLocale.en);
        expect(tester.takeException(), isNull);
        await _captureIfRequested(
          tester,
          fixture,
          'announcements-320-${layout.name}-en-delete-dialog',
        );
        await _closeDialog(tester, fixture);

        I18n.setLocale(AppLocale.zh);
        await tester.pumpAndSettle();
        await _openNewDialog(tester, AppLocale.zh);
        _expectEditorCopy(
          tester,
          AppLocale.zh,
          editing: false,
          selectedLevel: '普通',
        );
        await _expectLevelOptions(tester, AppLocale.zh);
        expect(tester.takeException(), isNull);
        await _captureIfRequested(
          tester,
          fixture,
          'announcements-320-${layout.name}-zh-new-form',
        );
        await _closeDialog(tester, fixture);

        await _openEditDialog(tester);
        _expectEditorCopy(
          tester,
          AppLocale.zh,
          editing: true,
          selectedLevel: '重要',
        );
        expect(tester.takeException(), isNull);
        await _captureIfRequested(
          tester,
          fixture,
          'announcements-320-${layout.name}-zh-edit-form',
        );
        await _closeDialog(tester, fixture);

        await _openDeleteDialog(tester);
        _expectDialogLocale(tester, AppLocale.zh);
        expect(tester.takeException(), isNull);
        await _captureIfRequested(
          tester,
          fixture,
          'announcements-320-${layout.name}-zh-delete-dialog',
        );
        await _closeDialog(tester, fixture);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Announcements empty state fits 320px and follows locale at text scale ${layout.scale}',
      (tester) async {
        final fixture = await _mountAnnouncements(
          tester,
          width: 320,
          textScale: layout.scale,
          empty: true,
        );
        final module = find.byKey(const ValueKey('admin-announcements-0'));
        expect(module, findsOneWidget);
        _expectModuleLocale(tester, module, AppLocale.zh);
        expect(tester.takeException(), isNull);
        await _captureIfRequested(
          tester,
          fixture,
          'announcements-320-${layout.name}-zh-empty',
        );

        final requestsBeforeLocale = List<String>.of(fixture.requestLines);
        I18n.setLocale(AppLocale.en);
        await tester.pumpAndSettle();
        _expectModuleLocale(tester, module, AppLocale.en);
        expect(fixture.requestLines, requestsBeforeLocale);
        expect(tester.takeException(), isNull);
        await _captureIfRequested(
          tester,
          fixture,
          'announcements-320-${layout.name}-en-empty',
        );
      },
    );
  }

  testWidgets(
    'Announcements search, filters, sort, and page selection persist across zh-en-zh',
    (tester) async {
      final fixture = await _mountAnnouncements(tester, totalAnnouncements: 60);
      final module = find.byKey(const ValueKey('admin-announcements-0'));
      final searchField = find
          .descendant(of: module, matching: find.byType(TextField))
          .first;
      await tester.enterText(searchField, 'Literal announcement');
      final searchController = tester
          .widget<TextField>(searchField)
          .controller!;
      searchController.selection = const TextSelection(
        baseOffset: 1,
        extentOffset: 8,
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(
        fixture.announcementReads.last.queryParameters['q'],
        'Literal announcement',
      );

      await _tapAnnouncementChip(tester, '已发布');
      expect(
        fixture.announcementReads.last.queryParameters['status'],
        'published',
      );
      await _tapAnnouncementChip(tester, '重要');
      expect(
        fixture.announcementReads.last.queryParameters['level'],
        'warning',
      );

      final createdSort = find.descendant(
        of: module,
        matching: find.text('最新创建优先'),
      );
      await tester.ensureVisible(createdSort);
      await tester.tap(createdSort);
      await tester.pumpAndSettle();
      final titleSort = find.text('标题 A-Z');
      expect(titleSort, findsOneWidget);
      await tester.tap(titleSort);
      await tester.pumpAndSettle();
      expect(
        fixture.announcementReads.last.queryParameters['sort'],
        'title_asc',
      );

      final pagination = find.byKey(
        const ValueKey('admin_announcements_pagination_bar'),
      );
      final nextPage = find.descendant(
        of: pagination,
        matching: find.byTooltip('下一页'),
      );
      expect(nextPage, findsOneWidget);
      await tester.tap(nextPage);
      await tester.pumpAndSettle();
      final requestAtSecondPage = fixture.announcementReads.last;
      expect(requestAtSecondPage.queryParameters, {
        'q': 'Literal announcement',
        'status': 'published',
        'level': 'warning',
        'sort': 'title_asc',
        'limit': '20',
        'offset': '20',
      });
      expect(find.textContaining('第 2/3 页'), findsOneWidget);
      await _revealAnnouncementHeader(tester);
      final selection = searchController.selection;
      final queryController = tester.widget<TextField>(searchField).controller;
      expect(searchController.text, 'Literal announcement');
      final requestsBeforeLocaleChanges = List<String>.of(fixture.requestLines);
      final moduleElement = tester.element(module);

      for (final locale in [AppLocale.en, AppLocale.zh]) {
        I18n.setLocale(locale);
        await tester.pumpAndSettle();
        expect(tester.element(module), same(moduleElement));
        expect(
          tester.widget<TextField>(searchField).controller,
          same(queryController),
        );
        expect(searchController.text, 'Literal announcement');
        expect(searchController.selection, selection);
        expect(
          tester
              .widget<ChoiceChip>(
                find.widgetWithText(
                  ChoiceChip,
                  locale == AppLocale.zh ? '已发布' : 'Published',
                ),
              )
              .selected,
          isTrue,
        );
        expect(
          tester
              .widget<ChoiceChip>(
                find.widgetWithText(
                  ChoiceChip,
                  locale == AppLocale.zh ? '重要' : 'Important',
                ),
              )
              .selected,
          isTrue,
        );
        expect(
          find.descendant(
            of: module,
            matching: find.text(
              locale == AppLocale.zh ? '标题 A-Z' : 'Title A–Z',
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: pagination,
            matching: find.textContaining(
              locale == AppLocale.zh ? '第 2/3 页' : 'Page 2/3',
            ),
          ),
          findsOneWidget,
        );
        expect(fixture.requestLines, requestsBeforeLocaleChanges);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'Announcements callbacks captured before leaving the tab stay invalid after returning',
    (tester) async {
      final fixture = await _mountAnnouncements(tester);
      final retainedMenu = _rowMenuCallback(tester);
      final retainedNewButton = _newAnnouncementCallback(tester);

      await _selectAdminTab(tester, '许愿与反馈');
      await _selectAdminTab(tester, '公告');
      expect(
        find.byKey(const ValueKey('admin-announcements-0')),
        findsOneWidget,
      );
      final requestsAfterReturn = List<String>.of(fixture.requestLines);

      retainedMenu('edit');
      retainedNewButton();
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(fixture.announcementMutations, isEmpty);
      expect(fixture.requestLines, requestsAfterReturn);

      final sameFrameMenu = _rowMenuCallback(tester);
      final sameFrameNewButton = _newAnnouncementCallback(tester);
      final tabController = tester
          .widget<TabBar>(find.byType(TabBar))
          .controller!;
      tabController.animateTo(7);
      tabController.animateTo(6);
      sameFrameMenu('edit');
      sameFrameNewButton();
      expect(fixture.announcementMutations, isEmpty);
      expect(fixture.requestLines, requestsAfterReturn);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(fixture.announcementMutations, isEmpty);
      final requestsAfterSameFrameReload = List<String>.of(
        fixture.requestLines,
      );
      sameFrameMenu('toggle');
      sameFrameNewButton();
      await tester.pumpAndSettle();
      expect(fixture.announcementMutations, isEmpty);
      expect(fixture.requestLines, requestsAfterSameFrameReload);

      await _revealAnnouncementCard(tester);
      final currentMenu = _rowMenuCallback(tester);
      currentMenu('edit');
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      await _closeDialog(tester, fixture);

      final currentNewButton = _newAnnouncementCallback(tester);
      currentNewButton();
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      await _closeDialog(tester, fixture);
      expect(fixture.announcementMutations, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'token and client replacement with same-frame tab changes clear stale announcement state',
    (tester) async {
      final fixture = await _mountAnnouncements(tester);
      final module = find.byKey(const ValueKey('admin-announcements-0'));
      final searchField = find
          .descendant(of: module, matching: find.byType(TextField))
          .first;
      await tester.enterText(searchField, 'Literal announcement');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      await _tapAnnouncementChip(tester, '已发布');
      await _tapAnnouncementChip(tester, '重要');
      expect(
        fixture.announcementReads.last.queryParameters['status'],
        'published',
      );
      expect(
        fixture.announcementReads.last.queryParameters['level'],
        'warning',
      );

      final heldRead = fixture.holdNextAnnouncementRead();
      await _revealAnnouncementHeader(tester);
      final publishedChip = find.widgetWithText(ChoiceChip, '已发布');
      await tester.ensureVisible(publishedChip);
      await tester.tap(publishedChip);
      await tester.pump();
      expect(
        fixture.announcementReads.last.queryParameters['q'],
        'Literal announcement',
      );

      const replacementTitle = 'New account announcement';
      fixture.replaceItems([
        {
          'id': 2201,
          'title': replacementTitle,
          'body': 'Replacement account body',
          'level': 'info',
          'published': 1,
          'created_at': '2026-10-02 08:00:00',
          'updated_at': '2026-10-02 08:00:00',
        },
      ]);
      const rotatedToken = 'rotated-announcement-admin-token';
      fixture.replaceAuth(
        AuthProvider(
          client: fixture.newClient(token: rotatedToken),
          initialState: _adminState(token: rotatedToken),
        ),
      );
      final tabController = tester
          .widget<TabBar>(find.byType(TabBar))
          .controller!;
      tabController.animateTo(7);
      tabController.animateTo(6);
      await tester.pumpAndSettle();
      expect(tabController.index, 6);
      await _revealAnnouncementHeader(tester);

      final currentSearch = find
          .descendant(
            of: find.byKey(const ValueKey('admin-announcements-0')),
            matching: find.byType(TextField),
          )
          .first;
      expect(tester.widget<TextField>(currentSearch).controller!.text, isEmpty);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '全部状态'))
            .selected,
        isTrue,
      );
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '全部级别'))
            .selected,
        isTrue,
      );
      expect(find.text('最新创建优先'), findsOneWidget);
      expect(find.textContaining('第 1/1 页'), findsOneWidget);
      expect(find.text(replacementTitle), findsOneWidget);
      expect(find.text(_announcementTitle), findsNothing);
      expect(
        fixture.announcementReads.last.queryParameters.containsKey('q'),
        isFalse,
      );
      expect(
        fixture.announcementReads.last.queryParameters.containsKey('status'),
        isFalse,
      );
      expect(
        fixture.announcementReads.last.queryParameters.containsKey('level'),
        isFalse,
      );

      heldRead.complete(
        _jsonResponse({
          'items': [
            {
              'id': _announcementId,
              'title': 'Stale account announcement',
              'body': 'Stale response body',
              'level': 'warning',
              'published': 1,
              'created_at': '2026-10-01 08:00:00',
              'updated_at': '2026-10-01 08:00:00',
            },
          ],
          'total': 1,
          'limit': 20,
          'offset': 0,
          'has_more': false,
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text(replacementTitle), findsOneWidget);
      expect(find.text('Stale account announcement'), findsNothing);
      expect(fixture.announcementMutations, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'announcement required title and body trim validation preserves draft and follows locale',
    (tester) async {
      final fixture = await _mountAnnouncements(tester);
      await _openNewDialog(tester, AppLocale.zh);
      final titleField = _dialogFields(tester)[0];
      final bodyField = _dialogFields(tester)[1];
      await tester.enterText(titleField, '   ');
      await tester.enterText(bodyField, _draftBody);
      final controllerBefore = tester.widget<TextField>(bodyField).controller!;
      final requestsBefore = List<String>.of(fixture.requestLines);

      await _tapDialogPrimary(tester);
      expect(find.byType(Dialog), findsOneWidget);
      expect(fixture.announcementMutations, isEmpty);
      expect(tester.widget<TextField>(titleField).controller!.text, '   ');
      expect(controllerBefore.text, _draftBody);
      final titleErrorZh = _fieldError(tester, 0);
      expect(titleErrorZh, isNotEmpty);
      expect(_cjk.hasMatch(titleErrorZh), isTrue);
      expect(fixture.requestLines, requestsBefore);

      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      final titleErrorEn = _fieldError(tester, 0);
      expect(titleErrorEn, isNotEmpty);
      expect(_cjk.hasMatch(titleErrorEn), isFalse, reason: titleErrorEn);
      expect(controllerBefore.text, _draftBody);

      await tester.enterText(titleField, _draftTitle);
      await tester.enterText(bodyField, '\n  ');
      await _tapDialogPrimary(tester);
      expect(find.byType(Dialog), findsOneWidget);
      expect(fixture.announcementMutations, isEmpty);
      expect(
        tester.widget<TextField>(titleField).controller!.text,
        _draftTitle,
      );
      expect(tester.widget<TextField>(bodyField).controller!.text, '\n  ');
      final bodyErrorEn = _fieldError(tester, 1);
      expect(bodyErrorEn, isNotEmpty);
      expect(_cjk.hasMatch(bodyErrorEn), isFalse, reason: bodyErrorEn);
      expect(fixture.requestLines, requestsBefore);

      I18n.setLocale(AppLocale.zh);
      await tester.pumpAndSettle();
      final bodyErrorZh = _fieldError(tester, 1);
      expect(bodyErrorZh, isNotEmpty);
      expect(_cjk.hasMatch(bodyErrorZh), isTrue, reason: bodyErrorZh);
      expect(
        tester.widget<TextField>(titleField).controller!.text,
        _draftTitle,
      );
      expect(tester.takeException(), isNull);
      await _closeDialog(tester, fixture);
    },
  );

  testWidgets(
    'create announcement trims payload and dispatches once from a retained save callback',
    (tester) async {
      final fixture = await _mountAnnouncements(tester);
      await _openNewDialog(tester, AppLocale.zh);
      final fields = _dialogFields(tester);
      await tester.enterText(fields[0], '  $_createdTitle  ');
      await tester.enterText(fields[1], '  $_createdBody  ');
      await _chooseLevel(tester, '普通', '紧急');
      await _tapPublishedSwitch(tester, AppLocale.zh);
      final held = fixture.holdNextMutation();
      final save = _primaryDialogCallback(tester);
      save();
      save();
      await tester.pumpAndSettle();

      expect(fixture.announcementMutations, hasLength(1));
      expect(fixture.announcementMutations.single.method, 'POST');
      expect(
        fixture.announcementMutations.single.path,
        '/api/admin/announcements',
      );
      expect(fixture.mutationBodies.single, {
        'title': _createdTitle,
        'body': _createdBody,
        'level': 'critical',
        'published': false,
      });
      expect(find.byType(Dialog), findsNothing);
      held.complete(_jsonResponse({'id': _createdId}));
      await tester.pumpAndSettle();
      expect(fixture.announcementMutations, hasLength(1));
      expect(fixture.announcementReads, hasLength(2));
      expect(find.text(_createdTitle), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'edit announcement submits the numeric id and exact trimmed payload once',
    (tester) async {
      final fixture = await _mountAnnouncements(tester);
      await _openEditDialog(tester);
      final fields = _dialogFields(tester);
      await tester.enterText(fields[0], '  $_editedTitle  ');
      await tester.enterText(fields[1], '  $_editedBody  ');
      await _chooseLevel(tester, '重要', '紧急');
      await _tapPublishedSwitch(tester, AppLocale.zh);
      final held = fixture.holdNextMutation();
      final save = _primaryDialogCallback(tester);
      save();
      save();
      await tester.pumpAndSettle();

      expect(fixture.announcementMutations, hasLength(1));
      expect(fixture.announcementMutations.single.method, 'PATCH');
      expect(
        fixture.announcementMutations.single.path,
        '/api/admin/announcements/$_announcementId',
      );
      expect(fixture.mutationBodies.single, {
        'title': _editedTitle,
        'body': _editedBody,
        'level': 'critical',
        'published': false,
      });
      held.complete(_jsonResponse({}));
      await tester.pumpAndSettle();
      expect(fixture.announcementMutations, hasLength(1));
      expect(fixture.announcementReads, hasLength(2));
      expect(find.text(_editedTitle), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'editing an unknown announcement level preserves it in the payload',
    (tester) async {
      final fixture = await _mountAnnouncements(tester, unknownLevel: true);
      await _openEditDialog(tester);
      final fields = _dialogFields(tester);
      await tester.enterText(fields[0], _draftTitle);
      await tester.enterText(fields[1], _draftBody);
      await _tapDialogPrimary(tester);
      await tester.pumpAndSettle();

      expect(fixture.announcementMutations, hasLength(1));
      expect(fixture.announcementMutations.single.method, 'PATCH');
      expect(
        fixture.announcementMutations.single.path,
        '/api/admin/announcements/$_announcementId',
      );
      expect(fixture.mutationBodies.single['level'], 'legacy-critical');
      expect(fixture.mutationBodies.single['title'], _draftTitle);
      expect(fixture.mutationBodies.single['body'], _draftBody);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'publish and unpublish success and error feedback use the live locale',
    (tester) async {
      final fixture = await _mountAnnouncements(tester);

      final heldUnpublish = fixture.holdNextMutation();
      final unpublish = _rowMenuCallback(tester);
      unpublish('toggle');
      unpublish('toggle');
      await tester.pumpAndSettle();
      expect(fixture.announcementMutations, hasLength(1));
      expect(fixture.announcementMutations.last.method, 'PATCH');
      expect(fixture.mutationBodies.last, {'published': false});
      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      heldUnpublish.complete(_jsonResponse({}));
      await tester.pumpAndSettle();
      _expectSnackLocale(tester, AppLocale.en);
      fixture.messengerKey.currentState!.clearSnackBars();
      await tester.pumpAndSettle();

      final heldPublishFailure = fixture.holdNextMutation();
      _rowMenuCallback(tester)('toggle');
      await tester.pumpAndSettle();
      expect(fixture.announcementMutations, hasLength(2));
      expect(fixture.mutationBodies.last, {'published': true});
      I18n.setLocale(AppLocale.zh);
      await tester.pumpAndSettle();
      heldPublishFailure.complete(
        _jsonResponse({'detail': 'synthetic publish failure'}, status: 500),
      );
      await tester.pumpAndSettle();
      _expectSnackLocale(tester, AppLocale.zh);
      fixture.messengerKey.currentState!.clearSnackBars();
      await tester.pumpAndSettle();

      final heldPublish = fixture.holdNextMutation();
      _rowMenuCallback(tester)('toggle');
      await tester.pumpAndSettle();
      expect(fixture.announcementMutations, hasLength(3));
      expect(fixture.mutationBodies.last, {'published': true});
      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      heldPublish.complete(_jsonResponse({}));
      await tester.pumpAndSettle();
      _expectSnackLocale(tester, AppLocale.en);
      fixture.messengerKey.currentState!.clearSnackBars();
      await tester.pumpAndSettle();

      final heldUnpublishFailure = fixture.holdNextMutation();
      _rowMenuCallback(tester)('toggle');
      await tester.pumpAndSettle();
      expect(fixture.announcementMutations, hasLength(4));
      expect(fixture.mutationBodies.last, {'published': false});
      I18n.setLocale(AppLocale.zh);
      await tester.pumpAndSettle();
      heldUnpublishFailure.complete(
        _jsonResponse({'detail': 'synthetic unpublish failure'}, status: 500),
      );
      await tester.pumpAndSettle();
      _expectSnackLocale(tester, AppLocale.zh);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('delete success and error feedback use the live locale', (
    tester,
  ) async {
    final fixture = await _mountAnnouncements(tester);

    final heldDeleteFailure = fixture.holdNextMutation();
    await _openDeleteDialog(tester);
    final confirmFailure = _primaryDialogCallback(tester);
    confirmFailure();
    confirmFailure();
    await tester.pumpAndSettle();
    expect(fixture.announcementMutations, hasLength(1));
    expect(fixture.announcementMutations.single.method, 'DELETE');
    expect(
      fixture.announcementMutations.single.path,
      '/api/admin/announcements/$_announcementId',
    );
    I18n.setLocale(AppLocale.en);
    await tester.pumpAndSettle();
    heldDeleteFailure.complete(
      _jsonResponse({'detail': 'synthetic delete failure'}, status: 500),
    );
    await tester.pumpAndSettle();
    _expectSnackLocale(tester, AppLocale.en);
    fixture.messengerKey.currentState!.clearSnackBars();
    await tester.pumpAndSettle();

    final heldDelete = fixture.holdNextMutation();
    await _openDeleteDialog(tester);
    final confirmDelete = _primaryDialogCallback(tester);
    confirmDelete();
    await tester.pumpAndSettle();
    expect(fixture.announcementMutations, hasLength(2));
    I18n.setLocale(AppLocale.zh);
    await tester.pumpAndSettle();
    heldDelete.complete(_jsonResponse({}));
    await tester.pumpAndSettle();
    _expectSnackLocale(tester, AppLocale.zh);
    expect(fixture.announcementReads, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'retained announcement menu callbacks reject account, client, token, and permission changes',
    (tester) async {
      for (final boundary in const [
        'account replacement',
        'client replacement',
        'token rotation',
        'permission revocation',
      ]) {
        final fixture = await _mountAnnouncements(tester);
        final retainedMenu = _rowMenuCallback(tester);
        _invalidateFixture(fixture, boundary);
        await tester.pumpAndSettle();
        final requestsBeforeCallback = List<String>.of(fixture.requestLines);

        retainedMenu('toggle');
        await tester.pumpAndSettle();
        expect(fixture.announcementMutations, isEmpty, reason: boundary);
        expect(fixture.requestLines, requestsBeforeCallback, reason: boundary);
        expect(find.byType(Dialog), findsNothing, reason: boundary);
        expect(tester.takeException(), isNull, reason: boundary);
      }
    },
  );

  testWidgets(
    'retained announcement confirmation rejects account, client, token, and permission changes',
    (tester) async {
      for (final boundary in const [
        'account replacement',
        'client replacement',
        'token rotation',
        'permission revocation',
      ]) {
        final fixture = await _mountAnnouncements(tester);
        await _openDeleteDialog(tester);
        final dialogRoute = fixture.routes.current;
        final retainedConfirm = _primaryDialogCallback(tester);
        _invalidateFixture(fixture, boundary);
        await tester.pumpAndSettle();
        final requestsBeforeCallback = List<String>.of(fixture.requestLines);

        retainedConfirm();
        await tester.pumpAndSettle();
        expect(fixture.announcementMutations, isEmpty, reason: boundary);
        expect(fixture.requestLines, requestsBeforeCallback, reason: boundary);
        expect(fixture.routes.current, same(dialogRoute), reason: boundary);
        expect(find.byType(Dialog), findsOneWidget, reason: boundary);
        expect(tester.takeException(), isNull, reason: boundary);
      }
    },
  );

  testWidgets(
    'covered announcement confirmation cannot pop the covering route or write',
    (tester) async {
      final fixture = await _mountAnnouncements(tester);
      await _openDeleteDialog(tester);
      final dialogRoute = fixture.routes.current;
      final retainedConfirm = _primaryDialogCallback(tester);
      final coveringRoute = MaterialPageRoute<void>(
        builder: (_) =>
            const Scaffold(body: Center(child: Text('covering route'))),
      );
      unawaited(fixture.navigatorKey.currentState!.push<void>(coveringRoute));
      await tester.pumpAndSettle();
      final requestsBeforeCallback = List<String>.of(fixture.requestLines);

      retainedConfirm();
      await tester.pumpAndSettle();
      expect(find.text('covering route'), findsOneWidget);
      expect(fixture.routes.current, same(coveringRoute));
      expect(fixture.announcementMutations, isEmpty);
      expect(fixture.requestLines, requestsBeforeCallback);
      expect(dialogRoute, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'announcement mutation completing after account change does not reload or announce',
    (tester) async {
      final fixture = await _mountAnnouncements(tester);
      await _openNewDialog(tester, AppLocale.zh);
      final fields = _dialogFields(tester);
      await tester.enterText(fields[0], _createdTitle);
      await tester.enterText(fields[1], _createdBody);
      final held = fixture.holdNextMutation();
      final save = _primaryDialogCallback(tester);
      save();
      save();
      await tester.pumpAndSettle();
      expect(fixture.announcementMutations, hasLength(1));

      fixture.replaceAuth(
        AuthProvider(
          client: fixture.client,
          initialState: _adminState(userId: 'replacement-admin'),
        ),
      );
      await tester.pumpAndSettle();
      final readsAfterAccountReplacement = List<String>.of(
        fixture.announcementReads.map((request) => request.line),
      );
      held.complete(_jsonResponse({'id': _createdId}));
      await tester.pumpAndSettle();

      expect(
        fixture.announcementReads.map((request) => request.line).toList(),
        readsAfterAccountReplacement,
      );
      expect(find.byType(SnackBar), findsNothing);
      expect(fixture.announcementMutations, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
  _registerAdminFullCopyCases2294();

}

Future<_AnnouncementsFixture> _mountAnnouncements(
  WidgetTester tester, {
  double width = 390,
  double height = 900,
  double textScale = 1,
  bool empty = false,
  bool unknownLevel = false,
  int totalAnnouncements = 14,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.runAsync(loadWidgetPolishScreenshotFonts);
  final fixture = _AnnouncementsFixture(
    empty: empty,
    unknownLevel: unknownLevel,
    totalAnnouncements: totalAnnouncements,
  );
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
            home: const AdminScreen(initialTabIndex: 6),
          ),
        );
      },
    ),
  );
  fixture.rebuildHost = rebuildHost;
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('admin-announcements-0')), findsOneWidget);
  expect(fixture.announcementReads, hasLength(1));
  expect(tester.takeException(), isNull);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });
  return fixture;
}

Future<void> _openNewDialog(WidgetTester tester, AppLocale locale) async {
  await _revealAnnouncementHeader(tester);
  final module = find.byKey(const ValueKey('admin-announcements-0'));
  final label = locale == AppLocale.zh ? '新增公告' : 'New announcement';
  final button = find.descendant(of: module, matching: find.text(label));
  expect(button, findsOneWidget);
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
  expect(find.byType(Dialog), findsOneWidget);
}

Future<void> _tapAnnouncementChip(WidgetTester tester, String label) async {
  await _revealAnnouncementHeader(tester);
  final chip = find.widgetWithText(ChoiceChip, label);
  expect(chip, findsOneWidget);
  await tester.ensureVisible(chip);
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

Finder _announcementScrollable() => find
    .descendant(
      of: find.descendant(
        of: find.byKey(const ValueKey('admin-announcements-0')),
        matching: find.byType(ListView),
      ),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
    )
    .first;

Future<void> _revealAnnouncementHeader(WidgetTester tester) async {
  final state = tester.state<ScrollableState>(_announcementScrollable());
  state.position.jumpTo(0);
  await tester.pumpAndSettle();
}

Future<void> _revealAnnouncementCard(WidgetTester tester) async {
  if (find.byType(PopupMenuButton<String>).evaluate().isNotEmpty) return;
  await _revealAnnouncementHeader(tester);
  await tester.scrollUntilVisible(
    find.byType(PopupMenuButton<String>),
    120,
    scrollable: _announcementScrollable(),
  );
  await tester.pumpAndSettle();
}

Future<void> _selectAdminTab(WidgetTester tester, String label) async {
  final tab = find.descendant(
    of: find.byType(TabBar),
    matching: find.text(label),
  );
  expect(tab, findsOneWidget);
  await tester.ensureVisible(tab);
  await tester.tap(tab);
  await tester.pumpAndSettle();
}

Future<void> _openEditDialog(WidgetTester tester) async {
  await _revealAnnouncementCard(tester);
  await _selectAnnouncementMenuAction(
    tester,
    I18n.current == AppLocale.zh ? '编辑' : 'Edit',
  );
  expect(find.byType(Dialog), findsOneWidget);
}

Future<void> _openDeleteDialog(WidgetTester tester) async {
  await _revealAnnouncementCard(tester);
  await _selectAnnouncementMenuAction(
    tester,
    I18n.current == AppLocale.zh ? '删除' : 'Delete',
  );
  expect(find.byType(Dialog), findsOneWidget);
}

Future<void> _selectAnnouncementMenuAction(
  WidgetTester tester,
  String label,
) async {
  await tester.ensureVisible(_rowMenuButton());
  await tester.tap(_rowMenuButton());
  await tester.pumpAndSettle();
  final item = find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate(
      (widget) => widget is PopupMenuItem<String>,
    ),
  );
  expect(item, findsOneWidget);
  await tester.tap(item);
  await tester.pumpAndSettle();
}

Future<void> _closeDialog(
  WidgetTester tester,
  _AnnouncementsFixture fixture,
) async {
  fixture.navigatorKey.currentState!.pop();
  await tester.pumpAndSettle();
  expect(find.byType(Dialog), findsNothing);
}

ValueChanged<String> _rowMenuCallback(WidgetTester tester) =>
    tester.widget<PopupMenuButton<String>>(_rowMenuButton()).onSelected!;

VoidCallback _newAnnouncementCallback(WidgetTester tester) {
  final module = find.byKey(const ValueKey('admin-announcements-0'));
  final label = I18n.current == AppLocale.zh ? '新增公告' : 'New announcement';
  final text = find.descendant(of: module, matching: find.text(label));
  expect(text, findsOneWidget);
  final button = find.ancestor(of: text, matching: find.byType(FilledButton));
  expect(button, findsOneWidget);
  return tester.widget<FilledButton>(button).onPressed!;
}

Finder _rowMenuButton() => find.byType(PopupMenuButton<String>).first;

List<Finder> _dialogFields(WidgetTester tester) {
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

Future<void> _tapDialogPrimary(WidgetTester tester) async {
  final dialog = find.byType(Dialog);
  final buttons = find.descendant(
    of: dialog,
    matching: find.byType(FilledButton),
  );
  await tester.tap(buttons.last);
  await tester.pumpAndSettle();
}

Future<void> _chooseLevel(
  WidgetTester tester,
  String selectedLabel,
  String optionLabel,
) async {
  final dialog = find.byType(Dialog);
  final selected = find.descendant(
    of: dialog,
    matching: find.text(selectedLabel),
  );
  expect(selected, findsOneWidget);
  await tester.tap(selected);
  await tester.pumpAndSettle();
  final option = find.text(optionLabel).last;
  expect(option, findsOneWidget);
  await tester.tap(option);
  await tester.pumpAndSettle();
}

Future<void> _tapPublishedSwitch(WidgetTester tester, AppLocale locale) async {
  final dialog = find.byType(Dialog);
  final label = locale == AppLocale.zh ? '立即发布' : 'Publish now';
  final switchTile = find.descendant(
    of: dialog,
    matching: find.byType(SwitchListTile),
  );
  expect(switchTile, findsOneWidget);
  expect(
    find.descendant(of: dialog, matching: find.text(label)),
    findsOneWidget,
  );
  await tester.tap(switchTile);
  await tester.pumpAndSettle();
}

String _fieldError(WidgetTester tester, int index) {
  final field = tester.widget<TextField>(_dialogFields(tester)[index]);
  return field.decoration?.errorText ?? '';
}

void _expectEditorCopy(
  WidgetTester tester,
  AppLocale locale, {
  required bool editing,
  required String selectedLevel,
}) {
  final dialog = find.byType(Dialog);
  expect(dialog, findsOneWidget);
  final title = editing
      ? (locale == AppLocale.zh ? '编辑公告' : 'Edit announcement')
      : null;
  final save = locale == AppLocale.zh ? '保存' : 'Save';
  final publish = locale == AppLocale.zh ? '立即发布' : 'Publish now';
  if (title != null) {
    expect(
      find.descendant(of: dialog, matching: find.text(title)),
      findsOneWidget,
    );
  }
  expect(
    find.descendant(of: dialog, matching: find.text(save)),
    findsOneWidget,
  );
  expect(
    find.descendant(of: dialog, matching: find.text(publish)),
    findsOneWidget,
  );
  expect(
    find.descendant(of: dialog, matching: find.text(selectedLevel)),
    findsOneWidget,
  );
  _expectDialogLocale(tester, locale);
}

Future<void> _expectLevelOptions(WidgetTester tester, AppLocale locale) async {
  final dialog = find.byType(Dialog);
  final selectedLabel = locale == AppLocale.zh ? '普通' : 'Info';
  final selected = find.descendant(
    of: dialog,
    matching: find.text(selectedLabel),
  );
  expect(selected, findsOneWidget);
  await tester.tap(selected);
  await tester.pumpAndSettle();
  final labels = locale == AppLocale.zh
      ? const ['普通', '重要', '紧急']
      : const ['Info', 'Important', 'Urgent'];
  for (final label in labels) {
    expect(find.text(label), findsWidgets, reason: label);
  }
  await tester.tap(find.text(selectedLabel).last);
  await tester.pumpAndSettle();
}

void _expectDialogLocale(WidgetTester tester, AppLocale locale) {
  final dialog = find.byType(Dialog);
  expect(dialog, findsOneWidget);
  final labels = <String>[
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
  ].map(_withoutAnnouncementUserText).where((text) => text.isNotEmpty).toList();
  expect(labels, isNotEmpty);
  if (locale == AppLocale.en) {
    expect(labels.where(_cjk.hasMatch), isEmpty, reason: labels.toString());
  } else {
    expect(labels.any(_cjk.hasMatch), isTrue, reason: labels.toString());
  }
}

void _expectModuleLocale(WidgetTester tester, Finder module, AppLocale locale) {
  final labels = tester
      .widgetList<Text>(
        find.descendant(of: module, matching: find.byType(Text)),
      )
      .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
      .map(_withoutAnnouncementUserText)
      .where((text) => text.isNotEmpty)
      .toList();
  expect(labels, isNotEmpty);
  if (locale == AppLocale.en) {
    expect(labels.where(_cjk.hasMatch), isEmpty, reason: labels.toString());
  } else {
    expect(labels.any(_cjk.hasMatch), isTrue, reason: labels.toString());
  }
}

String _withoutAnnouncementUserText(String text) {
  for (final data in [
    _announcementTitle,
    _announcementBody,
    _draftTitle,
    _draftBody,
    _createdTitle,
    _createdBody,
    _editedTitle,
    _editedBody,
  ]) {
    text = text.replaceAll(data, '');
  }
  return text.trim();
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

List<Element> _scrollableElements(WidgetTester tester, Finder module) => find
    .descendant(of: module, matching: find.byType(Scrollable))
    .evaluate()
    .toList();

int _scrollableIndexWithContent(WidgetTester tester, List<Element> elements) {
  for (var index = 0; index < elements.length; index++) {
    final state = tester.state<ScrollableState>(
      _elementFinder(elements[index]),
    );
    if (state.position.maxScrollExtent > 0) return index;
  }
  return 0;
}

Finder _elementFinder(Element element) =>
    find.byElementPredicate((candidate) => identical(candidate, element));

Future<void> _captureIfRequested(
  WidgetTester tester,
  _AnnouncementsFixture fixture,
  String name,
) async {
  final directoryPath =
      Platform.environment['DUOYI_ADMIN_ANNOUNCEMENTS_SCREENSHOT_DIR'];
  if (directoryPath == null || directoryPath.trim().isEmpty) return;
  final screenshotsRoot = Directory('evidence/screenshots').absolute.path;
  final outputDirectory = Directory(directoryPath).absolute.path;
  if (outputDirectory != screenshotsRoot &&
      !outputDirectory.startsWith(
        '$screenshotsRoot${Platform.pathSeparator}',
      )) {
    throw StateError(
      'DUOYI_ADMIN_ANNOUNCEMENTS_SCREENSHOT_DIR must stay under evidence/screenshots/.',
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

void _invalidateFixture(_AnnouncementsFixture fixture, String boundary) {
  switch (boundary) {
    case 'account replacement':
      fixture.replaceAuth(
        AuthProvider(
          client: fixture.client,
          initialState: _adminState(userId: 'replacement-admin'),
        ),
      );
      return;
    case 'client replacement':
      fixture.replaceClient(
        fixture.newClient(token: 'replacement-client-token'),
      );
      return;
    case 'token rotation':
      fixture.client.token = 'rotated-synthetic-admin-token';
      return;
    case 'permission revocation':
      fixture.replaceAuth(
        AuthProvider(
          client: fixture.client,
          initialState: _adminState(permissions: const ['__none__']),
        ),
      );
      return;
  }
}

AuthState _adminState({
  String userId = 'announcement-admin',
  String token = 'synthetic-admin-token',
  List<String> permissions = const ['announcements'],
}) => AuthState(
  userId: userId,
  username: 'admin',
  token: token,
  isAdmin: true,
  adminPermissions: permissions,
);

http.Response _jsonResponse(Object body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);

class _AnnouncementsFixture {
  _AnnouncementsFixture({
    this.empty = false,
    this.unknownLevel = false,
    this.totalAnnouncements = 14,
  }) {
    _items = empty
        ? <Map<String, dynamic>>[]
        : _initialItems(unknownLevel, count: totalAnnouncements);
    auth = _SwitchableClientAuth(
      client: newClient(token: 'synthetic-admin-token'),
      state: _adminState(),
    );
    authProviders.add(auth);
  }

  final bool empty;
  final bool unknownLevel;
  final int totalAnnouncements;
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
  late List<Map<String, dynamic>> _items;
  late AuthProvider auth;
  late StateSetter rebuildHost;
  Completer<http.Response>? _nextMutation;
  Completer<http.Response>? _nextAnnouncementRead;
  int _nextId = _announcementId + 1;

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

  Completer<http.Response> holdNextAnnouncementRead() {
    final completer = Completer<http.Response>();
    _nextAnnouncementRead = completer;
    return completer;
  }

  void replaceItems(List<Map<String, dynamic>> items) {
    _items = items;
  }

  List<_CapturedRequest> get announcementReads => requests
      .where(
        (request) =>
            request.method == 'GET' &&
            request.path == '/api/admin/announcements',
      )
      .toList();

  List<_CapturedRequest> get announcementMutations => requests
      .where(
        (request) =>
            request.path.startsWith('/api/admin/announcements') &&
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

    if (request.method == 'GET') {
      if (request.url.path == '/api/admin/announcements') {
        final held = _nextAnnouncementRead;
        _nextAnnouncementRead = null;
        if (held != null) return held.future;
        final limit =
            int.tryParse(request.url.queryParameters['limit'] ?? '') ?? 20;
        final offset =
            int.tryParse(request.url.queryParameters['offset'] ?? '') ?? 0;
        final items = _items.skip(offset).take(limit).toList();
        return _jsonResponse({
          'items': items,
          'total': _items.length,
          'limit': limit,
          'offset': offset,
          'has_more': offset + items.length < _items.length,
        });
      }
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
            'announcements': <String, Object>{
              'total': _items.length,
              'published': _items.length,
            },
            'invites': <String, Object>{'total': 0, 'used': 0},
            'registration_series': <Object>[],
          });
        case '/api/admin/settings':
          return _jsonResponse({
            'invite_code_required': false,
            'registration_enabled': true,
            'registration_email_required': false,
            'maintenance_mode': false,
            'force_update_required': false,
            'default_registration_coins': 100,
          });
        default:
          return emptyPage;
      }
    }

    if (request.url.path.startsWith('/api/admin/announcements')) {
      if (request.body.isNotEmpty) {
        mutationBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
      } else {
        mutationBodies.add(<String, dynamic>{});
      }
      final held = _nextMutation;
      _nextMutation = null;
      final response = held == null
          ? _defaultMutationResponse(request)
          : await held.future;
      if (response.statusCode >= 400) return response;
      if (request.method == 'POST') {
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        _items.insert(0, {
          'id': _nextId++,
          ...payload,
          'created_at': '2026-10-01 08:00:00',
          'updated_at': '2026-10-01 08:00:00',
        });
      } else {
        final id = int.parse(request.url.path.split('/').last);
        final index = _items.indexWhere(
          (item) => (item['id'] as num).toInt() == id,
        );
        if (index >= 0 && request.method == 'PATCH') {
          _items[index] = {
            ..._items[index],
            ...jsonDecode(request.body) as Map<String, dynamic>,
          };
        } else if (index >= 0 && request.method == 'DELETE') {
          _items.removeAt(index);
        }
      }
      return response;
    }

    throw StateError(
      'Unexpected Announcements fixture request: ${captured.line}',
    );
  }

  http.Response _defaultMutationResponse(http.Request request) {
    if (request.method == 'POST') return _jsonResponse({'id': _nextId});
    return _jsonResponse({});
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

List<Map<String, dynamic>> _initialItems(bool unknownLevel, {int count = 14}) =>
    [
      {
        'id': _announcementId,
        'title': _announcementTitle,
        'body': _announcementBody,
        'level': unknownLevel ? 'legacy-critical' : 'warning',
        'published': 1,
        'created_at': '2026-10-01 08:00:00',
        'updated_at': '2026-10-01 08:00:00',
      },
      for (var index = 1; index < count; index++)
        {
          'id': _announcementId + index,
          'title': 'Literal announcement $index',
          'body': 'Literal body $index',
          'level': 'info',
          'published': index.isEven ? 1 : 0,
          'created_at': '2026-10-01 08:00:00',
          'updated_at': '2026-10-01 08:00:00',
        },
    ];

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

// NEW2294 additions. Existing bodies, hooks and helper defaults are unchanged.
const _fullCopyRemoteTotal2294 = 19999980;
const _fullCopyLocalCount2294 = 20;

void _registerAdminFullCopyCases2294() {
  for (final brand in const ['defaultBrand', 'liquidGlass']) {
    for (final locale in const [AppLocale.zh, AppLocale.en]) {
      testWidgets(
        'Admin full copy 2294 $brand ${locale.name} 320x844 scale 2.0',
        (tester) async {
          final name = 'admin-full-copy-2294-$brand-${locale.name}';
          final fixture = await _mountAdminFullCopy2294(tester, brand, locale, name);
          final errors = <String>[];
          final module = find.byKey(const ValueKey('admin-announcements-0'));
          final title = find.descendant(of: module, matching: find.text(_announcementTitle));
          final expectedSummary = locale == AppLocale.zh
              ? '第 1-20 条 / 共 19999980 条 · 第 1/999999 页'
              : '1-20 of 19999980 · Page 1/999999';
          final summary = find.descendant(
            of: find.byKey(const ValueKey('admin_announcements_pagination_bar')),
            matching: find.text(expectedSummary),
          );
          try {
            await tester.scrollUntilVisible(
              title, 120, scrollable: _announcementScrollable(), maxScrolls: 20,
            );
            await tester.ensureVisible(title);
            await tester.pumpAndSettle();
          } catch (error) {
            errors.add('title reveal: $error');
          }
          await _captureAdminFullCopy2294(
            tester, fixture, '$name-title', title, _announcementTitle,
            role: 'authored-title', errors: errors,
          );
          // The footer is outside the list; use public viewport revelation.
          try {
            await tester.ensureVisible(summary);
            await tester.pumpAndSettle();
          } catch (error) {
            errors.add('pagination reveal: $error');
          }
          await _captureAdminFullCopy2294(
            tester, fixture, '$name-pagination', summary, expectedSummary,
            role: 'range-count-current-total-pages', errors: errors,
          );
          // Both measurement stages run before business assertions.
          // With capture enabled, each PNG precedes its paragraph measurement.
          expect(errors, isEmpty, reason: '$name retained evidence');
          expect(fixture.base.theme.brand.id, brand);
          expect(fixture.base._items, hasLength(_fullCopyLocalCount2294));
          expect(fixture.base.announcementReads, hasLength(1));
          expect(fixture.base.announcementMutations, isEmpty);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

class _AdminFullCopyFixture2294 {
  _AdminFullCopyFixture2294(this.base, this.fonts, this.output, this.brand, this.locale);
  final _AnnouncementsFixture base;
  final Map<String, Object?> fonts;
  final Directory? output;
  final String brand;
  final AppLocale locale;
}

Future<_AdminFullCopyFixture2294> _mountAdminFullCopy2294(
  WidgetTester tester, String brand, AppLocale locale, String name,
) async {
  final directoryPath = Platform.environment['DUOYI_ADMIN_FULL_COPY_2294_SCREENSHOT_DIR'];
  Directory? output;
  if (directoryPath != null && directoryPath.trim().isNotEmpty) {
    final requestedOutput = Directory(directoryPath).absolute;
    final root = Directory('/home/ubuntu/duoyi/evidence/screenshots');
    final runtimeAlias = Link(
      '/home/ubuntu/duoyi/.dart_tool/native-busy-acceptance-20261024-v177/evidence/screenshots',
    );
    // NEW2311: bind the existing central alias; never create or replace it.
    if (FileSystemEntity.typeSync(root.path, followLinks: false) !=
            FileSystemEntityType.directory ||
        root.resolveSymbolicLinksSync() != root.path ||
        FileSystemEntity.typeSync(runtimeAlias.path, followLinks: false) !=
            FileSystemEntityType.link ||
        runtimeAlias.targetSync() != root.path ||
        runtimeAlias.resolveSymbolicLinksSync() != root.path) {
      throw StateError('2311 central screenshot root/verified runtime alias changed.');
    }
    if (requestedOutput.path.split(Platform.pathSeparator).contains('..')) {
      throw StateError('2311 refuses screenshot path traversal.');
    }
    final rootPrefix = root.path + Platform.pathSeparator;
    final aliasPrefix = runtimeAlias.path + Platform.pathSeparator;
    final String relativeOutput;
    if (requestedOutput.path.startsWith(rootPrefix)) {
      relativeOutput = requestedOutput.path.substring(rootPrefix.length);
    } else if (requestedOutput.path.startsWith(aliasPrefix)) {
      relativeOutput = requestedOutput.path.substring(aliasPrefix.length);
    } else {
      throw StateError('2311 output must stay under the bound central screenshots root.');
    }
    for (final start in [requestedOutput, root, runtimeAlias.parent]) {
      for (var cursor = start; cursor.path != cursor.parent.path; cursor = cursor.parent) {
        if (FileSystemEntity.isLinkSync(cursor.path) &&
            cursor.path != runtimeAlias.path) {
          throw StateError('2311 refuses an unbound screenshot symlink: ${cursor.path}');
        }
      }
    }
    final segments = relativeOutput.split(Platform.pathSeparator)
        .where((segment) => segment.isNotEmpty && segment != '.').toList();
    if (segments.isEmpty) {
      throw StateError('2311 requires a named screenshot batch below the central root.');
    }
    // Persist using the central real path regardless of which admitted entry was used.
    output = Directory(rootPrefix + segments.join(Platform.pathSeparator));
  }
  SharedPreferences.setMockInitialValues({
    'theme_shop_state': jsonEncode({
      'activeBrand': brand, 'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
    }),
  });
  addTearDown(() => SharedPreferences.setMockInitialValues({}));
  I18n.setLocale(locale);
  tester.view.physicalSize = const Size(320, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // Remote total never reaches _initialItems/count or List.generate.
  final base = _AnnouncementsFixture(totalAnnouncements: _fullCopyLocalCount2294);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    base.dispose();
  });
  final fonts = await tester.runAsync<Map<String, Object?>>(() async {
    await base.theme.loadFromStorage();
    final rows = <Map<String, Object?>>[];
    final latinFamily = 'AdminFullCopy2294Latin-$name';
    final cjkFamily = 'AdminFullCopy2294Cjk-$name';
    final systemLatin = File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf');
    final defaultLatinPath = systemLatin.existsSync()
        ? systemLatin.path
        : 'assets/fonts/DejaVuSans.ttf';
    for (final entry in [
      (family: latinFamily, path: Platform.environment['DUOYI_WIDGET_SCREENSHOT_LATIN_FONT']
          ?? defaultLatinPath),
      (family: cjkFamily, path: 'assets/fonts/DroidSansFallbackFull.ttf'),
      (family: 'MaterialIcons', path: 'build/unit_test_assets/fonts/MaterialIcons-Regular.otf'),
    ]) {
      final file = File(entry.path);
      final bytes = file.readAsBytesSync();
      final digest = sha256.convert(bytes).toString();
      await (FontLoader(entry.family)
        ..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      if (sha256.convert(file.readAsBytesSync()).toString() != digest) {
        throw StateError('Font changed during registration: ${file.path}');
      }
      rows.add({
        'family': entry.family, 'path': file.absolute.path,
        'resolvedPath': file.resolveSymbolicLinksSync(),
        'bytes': bytes.length, 'sha256RegisteredBytes': digest,
      });
    }
    await PaintingBinding.instance.handleSystemMessage(<String, dynamic>{'type': 'fontsChange'});
    return {'latinFamily': latinFamily, 'cjkFamily': cjkFamily, 'registered': rows};
  });
  if (fonts == null) {
    throw StateError('2294 font/theme admission failed; inspect takeException.');
  }
  final transport = MockClient((request) async {
    final response = await base._handle(request);
    if (request.method != 'GET' ||
        request.url.path != '/api/admin/announcements') {
      return response;
    }
    final page = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    // Original handler records the real request and allocates only this page.
    page['total'] = _fullCopyRemoteTotal2294;
    page['has_more'] = true;
    return _jsonResponse(page);
  });
  base.transports.add(transport);
  base.replaceClient(ApiClient(
    baseUrl: 'https://duoyi.test', token: 'synthetic-admin-token', httpClient: transport,
  ));
  final brandTheme = base.theme.brand.theme;
  final latin = fonts['latinFamily']! as String;
  final fallback = [fonts['cjkFamily']! as String];
  final renderTheme = brandTheme.copyWith(
    // Replace families only; retain brand sizes, heights, colors and spacing.
    textTheme: brandTheme.textTheme.apply(fontFamily: latin, fontFamilyFallback: fallback),
    primaryTextTheme: brandTheme.primaryTextTheme.apply(
      fontFamily: latin, fontFamilyFallback: fallback,
    ),
  );
  late StateSetter rebuildHost;
  await tester.pumpWidget(StatefulBuilder(builder: (context, setState) {
    rebuildHost = setState;
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: base.auth),
        ChangeNotifierProvider<ThemeProvider>.value(value: base.theme),
      ],
      child: MaterialApp(
        locale: Locale(locale.name), supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        navigatorKey: base.navigatorKey, navigatorObservers: [base.routes],
        scaffoldMessengerKey: base.messengerKey, theme: renderTheme,
        builder: (context, child) => RepaintBoundary(
          key: base.screenshotKey,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
        ),
        home: const AdminScreen(initialTabIndex: 6),
      ),
    );
  }));
  base.rebuildHost = rebuildHost;
  await tester.pumpAndSettle();
  return _AdminFullCopyFixture2294(base, fonts, output, brand, locale);
}

List<double> _rectAdminFullCopy2294(Rect rect) =>
    [rect.left, rect.top, rect.right, rect.bottom];

Map<String, Object?> _measureAdminFullCopy2294(
  WidgetTester tester, RenderRepaintBoundary boundary, Finder target,
  String expected, String role, List<String> errors,
) {
  final richText = find.descendant(of: target, matching: find.byType(RichText));
  final paragraph = tester.renderObject<RenderParagraph>(richText);
  final element = tester.element(target);
  final actual = paragraph.text.toPlainText();
  Rect inBoundary(RenderBox box) => MatrixUtils.transformRect(
    box.getTransformTo(boundary), Offset.zero & box.size,
  );
  final rect = inBoundary(paragraph);
  var viewport = Offset.zero & boundary.size;
  final scroll = Scrollable.maybeOf(element, axis: Axis.vertical);
  if (scroll != null) {
    viewport = viewport.intersect(inBoundary(
      tester.renderObject<RenderBox>(find.byWidget(scroll.widget)),
    ));
  } else {
    viewport = viewport.intersect(inBoundary(tester.renderObject<RenderBox>(
      find.byKey(const ValueKey('admin_announcements_pagination_bar')),
    )));
  }
  final transform = paragraph.getTransformTo(boundary);
  Rect globalBox(ui.TextBox box) => MatrixUtils.transformRect(
    transform, Rect.fromLTRB(box.left, box.top, box.right, box.bottom),
  );
  bool contains(Rect box) =>
      box.left >= viewport.left - 0.5 && box.right <= viewport.right + 0.5 &&
      box.top >= viewport.top - 0.5 && box.bottom <= viewport.bottom + 0.5;
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: expected.length),
  );
  final missingGlyphs = <Map<String, Object?>>[];
  final clippedGlyphs = <Map<String, Object?>>[];
  var offset = 0;
  for (final rune in expected.runes) {
    final character = String.fromCharCode(rune);
    final end = offset + character.length;
    if (character.trim().isNotEmpty) {
      final glyphBoxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: offset, extentOffset: end),
      );
      if (glyphBoxes.isEmpty) {
        missingGlyphs.add({'offset': offset, 'character': character});
      } else if (!glyphBoxes.map(globalBox).every(contains)) {
        clippedGlyphs.add({'offset': offset, 'character': character});
      }
    }
    offset = end;
  }
  final natural = TextPainter(
    text: paragraph.text, textAlign: paragraph.textAlign,
    textDirection: paragraph.textDirection, textScaler: paragraph.textScaler,
    locale: paragraph.locale, strutStyle: paragraph.strutStyle,
    textWidthBasis: paragraph.textWidthBasis, textHeightBehavior: paragraph.textHeightBehavior,
  )..layout(maxWidth: paragraph.size.width);
  final row = <String, Object?>{
    'role': role, 'expected': expected, 'actual': actual,
    'fontFamily': paragraph.text.style?.fontFamily,
    'fontFallback': paragraph.text.style?.fontFamilyFallback,
    'fontSize': paragraph.text.style?.fontSize,
    'scaledFontSize': paragraph.text.style?.fontSize == null ? null
        : paragraph.textScaler.scale(paragraph.text.style!.fontSize!),
    'textScaleAt12': paragraph.textScaler.scale(12) / 12,
    'maxLines': paragraph.maxLines, 'overflow': paragraph.overflow.name,
    'softWrap': paragraph.softWrap, 'didExceedMaxLines': paragraph.didExceedMaxLines,
    'paragraphRect': _rectAdminFullCopy2294(rect),
    'visibleViewportRect': _rectAdminFullCopy2294(viewport),
    'paragraphSize': [paragraph.size.width, paragraph.size.height],
    'laidOutTextSize': [paragraph.textSize.width, paragraph.textSize.height],
    'unlimitedTextSize': [natural.width, natural.height],
    'unlimitedLineCount': natural.computeLineMetrics().length,
    'selectionBoxes': boxes.map((box) => _rectAdminFullCopy2294(globalBox(box))).toList(),
    'missingGlyphs': missingGlyphs, 'clippedGlyphs': clippedGlyphs,
    'scrollOffset': scroll?.position.pixels, 'maxScrollExtent': scroll?.position.maxScrollExtent,
  };
  final complete = actual == expected && !paragraph.didExceedMaxLines &&
      (paragraph.textScaler.scale(12) / 12 - 2).abs() < 0.001 &&
      boxes.isNotEmpty && missingGlyphs.isEmpty && clippedGlyphs.isEmpty &&
      boxes.map(globalBox).every(contains) &&
      paragraph.textSize.width <= paragraph.size.width + 0.5 &&
      paragraph.textSize.height <= paragraph.size.height + 0.5 &&
      natural.height <= paragraph.size.height + 0.5;
  natural.dispose();
  row['completeAtCapturedViewport'] = complete;
  if (!complete) errors.add('$role: incomplete paragraph or viewport');
  return row;
}

Future<void> _captureAdminFullCopy2294(
  WidgetTester tester, _AdminFullCopyFixture2294 fixture, String name,
  Finder target, String expected, {
  required String role, required List<String> errors,
}) async {
  final boundary = fixture.base.screenshotKey.currentContext!.findRenderObject()!
      as RenderRepaintBoundary;
  final output = fixture.output;
  Map<String, Object?>? picture;
  if (output != null) {
    final png = File('${output.path}/$name.png');
    final json = File('${output.path}/$name.json');
    if (png.existsSync() || json.existsSync()) {
      throw StateError('2294 refuses to overwrite retained evidence: $name');
    }
    // Persist PNG before paragraph measurement can fail.
    picture = await tester.runAsync<Map<String, Object?>>(() async {
      final budget = await Process.run('/usr/bin/python3', [
        '/home/ubuntu/duoyi/scripts/disk_budget.py', 'check',
      ]);
      if (budget.exitCode != 0) {
        throw StateError('Admin screenshot disk admission failed: ${budget.stdout}${budget.stderr}');
      }
      final image = await boundary.toImage(pixelRatio: 1);
      try {
        final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        png.parent.createSync(recursive: true);
        png.writeAsBytesSync(bytes);
        return {'path': png.absolute.path, 'width': image.width, 'height': image.height,
          'bytes': bytes.length, 'sha256': sha256.convert(bytes).toString()};
      } finally {
        image.dispose();
      }
    });
    if (picture == null) errors.add('PNG capture failed: $name');
  }
  Map<String, Object?> measurement;
  try {
    measurement = _measureAdminFullCopy2294(
      tester, boundary, target, expected, role, errors,
    );
  } catch (error, stack) {
    errors.add('$role measurement: $error');
    measurement = {'role': role, 'expected': expected, 'measurementError': '$error',
      'stack': '$stack', 'completeAtCapturedViewport': false};
  }
  for (var index = 0; index < 10; index++) {
    final exception = tester.takeException();
    if (exception == null) break;
    errors.add('Flutter exception: $exception');
  }
  if (fixture.base.theme.brand.id != fixture.brand) errors.add('Requested brand was not mounted');
  if (I18n.current != fixture.locale) errors.add('Requested locale was not mounted');
  final metadata = <String, Object?>{
    'case': name, 'kind': 'real-AdminScreen-widget-harness',
    'requestedBrand': fixture.brand, 'actualBrand': fixture.base.theme.brand.id,
    'requestedLocale': fixture.locale.name, 'activeLocale': I18n.current.name,
    'physicalSize': [tester.view.physicalSize.width, tester.view.physicalSize.height],
    'devicePixelRatio': tester.view.devicePixelRatio,
    'boundarySize': [boundary.size.width, boundary.size.height],
    'fonts': fixture.fonts, 'localItemsAllocated': fixture.base._items.length,
    'remoteTotal': _fullCopyRemoteTotal2294, 'remoteTotalPages': 999999,
    'requestLines': fixture.base.requestLines, 'measurement': measurement,
    'errorsSoFar': List<String>.of(errors), 'png': picture, 'deviceAcceptance': false,
  };
  if (output != null) {
    final json = File('${output.path}/$name.json');
    await tester.runAsync(() async {
      final product = File('lib/screens/admin_screen.dart');
      metadata['productSource'] = {'path': product.absolute.path,
        'bytes': product.lengthSync(),
        'sha256': sha256.convert(product.readAsBytesSync()).toString()};
      json.parent.createSync(recursive: true);
      json.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(metadata)}\n');
    });
  }
}
