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
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import '../support/widget_polish_screenshot_font.dart';

const _unusedCode = 'INV-LITERAL-001';
const _usedCode = 'INV-LITERAL-USED';
const _literalNote = 'Literal invite note 保留';
const _searchDraft = '  INV-LITERAL  ';
const _searchQuery = 'INV-LITERAL';
const _generatedNote = 'Generated note 原文';
const _deleteFailure = 'synthetic invite delete failure';

Finder _inviteModule() => find.byKey(const ValueKey('admin-invites-0'));

void main() {
  setUp(() => I18n.setLocale(AppLocale.zh));
  tearDown(() => I18n.setLocale(AppLocale.zh));

  testWidgets(
    'Invites GET contract and zh-en-zh preserve query, selection, focus, and scroll',
    (tester) async {
      final fixture = await _mountInvites(tester, codeCount: 24);
      expect(fixture.inviteReads, hasLength(1));
      expect(fixture.inviteReads.single.method, 'GET');
      expect(fixture.inviteReads.single.path, '/api/admin/invite-codes');
      expect(fixture.inviteReads.single.queryParameters, {
        'sort': 'created_desc',
        'limit': '20',
        'offset': '0',
      });

      final module = _inviteModule();
      final moduleElement = tester.element(module);
      final search = _searchField(tester);
      await tester.ensureVisible(search);
      await tester.enterText(search, _searchDraft);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(fixture.inviteReads.last.queryParameters['q'], _searchQuery);
      expect(fixture.inviteReads.last.queryParameters['sort'], 'created_desc');

      await _tapStatusChip(tester, 'unused');
      expect(fixture.inviteReads.last.queryParameters['q'], _searchQuery);
      expect(fixture.inviteReads.last.queryParameters['status'], 'unused');
      expect(fixture.inviteReads.last.queryParameters['limit'], '20');
      expect(fixture.inviteReads.last.queryParameters['offset'], '0');

      final scrollableElement = _scrollableWithContent(tester, module);
      final scrollable = tester.state<ScrollableState>(
        _elementFinder(scrollableElement),
      );
      expect(scrollable.position.maxScrollExtent, greaterThan(40));
      scrollable.position.jumpTo(24);
      await tester.pumpAndSettle();

      await tester.tap(search);
      final controller = tester.widget<TextField>(search).controller!;
      controller.selection = const TextSelection(
        baseOffset: 2,
        extentOffset: 12,
      );
      final selection = controller.selection;
      final focusNode = tester
          .widget<EditableText>(
            find.descendant(of: search, matching: find.byType(EditableText)),
          )
          .focusNode;
      expect(FocusManager.instance.primaryFocus, same(focusNode));
      final readsBeforeLocaleChanges = List<String>.of(fixture.requestLines);
      final scrollOffset = scrollable.position.pixels;

      for (final locale in [AppLocale.en, AppLocale.zh]) {
        I18n.setLocale(locale);
        await tester.pumpAndSettle();
        expect(tester.element(module), same(moduleElement));
        expect(
          tester.state<ScrollableState>(_elementFinder(scrollableElement)),
          same(scrollable),
        );
        expect(scrollable.position.pixels, scrollOffset);
        expect(
          tester.widget<TextField>(_searchField(tester)).controller,
          same(controller),
        );
        expect(controller.text, _searchDraft);
        expect(controller.selection, selection);
        expect(FocusManager.instance.primaryFocus, same(focusNode));
        expect(fixture.requestLines, readsBeforeLocaleChanges);
        _expectSearchCopy(tester, locale);
        expect(
          tester
              .widget<ChoiceChip>(
                find.widgetWithText(
                  ChoiceChip,
                  _localeText('未使用', 'Unused', locale),
                ),
              )
              .selected,
          isTrue,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  for (final layout in const [
    (width: 320.0, height: 900.0, textScale: 1.6, name: '320-1_6'),
    (width: 320.0, height: 900.0, textScale: 2.0, name: '320-2_0'),
    (width: 390.0, height: 900.0, textScale: 1.0, name: '390-1_0'),
    (width: 320.0, height: 540.0, textScale: 1.6, name: '320-short-1_6'),
  ]) {
    testWidgets(
      'Invites populated, empty, generate, result, and delete states fit ${layout.name}',
      (tester) async {
        final fixture = await _mountInvites(
          tester,
          width: layout.width,
          height: layout.height,
          textScale: layout.textScale,
          codeCount: 5,
        );
        _expectListCopy(tester, AppLocale.zh, populated: true);
        await _captureIfRequested(
          tester,
          fixture,
          'invites-${layout.name}-zh-populated',
        );
        I18n.setLocale(AppLocale.en);
        await tester.pumpAndSettle();
        _expectListCopy(tester, AppLocale.en, populated: true);
        await _captureIfRequested(
          tester,
          fixture,
          'invites-${layout.name}-en-populated',
        );

        I18n.setLocale(AppLocale.zh);
        await tester.pumpAndSettle();
        await _openGenerationDialog(tester);
        _expectGenerationDialog(tester, AppLocale.zh);
        await _captureIfRequested(
          tester,
          fixture,
          'invites-${layout.name}-zh-generate',
        );
        I18n.setLocale(AppLocale.en);
        await tester.pumpAndSettle();
        _expectGenerationDialog(tester, AppLocale.en);
        await _captureIfRequested(
          tester,
          fixture,
          'invites-${layout.name}-en-generate',
        );
        await _tapDialogAction(tester, '取消', 'Cancel');

        I18n.setLocale(AppLocale.zh);
        await tester.pumpAndSettle();
        await _openDeleteDialog(tester);
        _expectDeleteDialog(tester, AppLocale.zh, _unusedCode);
        await _captureIfRequested(
          tester,
          fixture,
          'invites-${layout.name}-zh-delete',
        );
        I18n.setLocale(AppLocale.en);
        await tester.pumpAndSettle();
        _expectDeleteDialog(tester, AppLocale.en, _unusedCode);
        await _captureIfRequested(
          tester,
          fixture,
          'invites-${layout.name}-en-delete',
        );
        await _tapDialogAction(tester, '取消', 'Cancel');

        I18n.setLocale(AppLocale.zh);
        await tester.pumpAndSettle();
        final codes = await _generateAndShowResult(
          tester,
          fixture,
          count: 2,
          note: 'layout note 保留',
        );
        _expectResultDialog(tester, AppLocale.zh, codes);
        await _captureIfRequested(
          tester,
          fixture,
          'invites-${layout.name}-zh-result',
        );
        I18n.setLocale(AppLocale.en);
        await tester.pumpAndSettle();
        _expectResultDialog(tester, AppLocale.en, codes);
        await _captureIfRequested(
          tester,
          fixture,
          'invites-${layout.name}-en-result',
        );
        fixture.navigatorKey.currentState!.pop();
        await tester.pumpAndSettle();

        fixture.codes.clear();
        await _returnToInviteHeader(tester);
        await tester.tap(_refreshButton());
        await tester.pumpAndSettle();
        I18n.setLocale(AppLocale.zh);
        await tester.pumpAndSettle();
        _expectListCopy(tester, AppLocale.zh, populated: false);
        await _captureIfRequested(
          tester,
          fixture,
          'invites-${layout.name}-zh-empty',
        );
        I18n.setLocale(AppLocale.en);
        await tester.pumpAndSettle();
        _expectListCopy(tester, AppLocale.en, populated: false);
        await _captureIfRequested(
          tester,
          fixture,
          'invites-${layout.name}-en-empty',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Long code, note, and used account data wrap at 320px and 2x text without translation',
    (tester) async {
      final fixture = await _mountInvites(tester, width: 320, textScale: 2);
      const unused = 'INV-UNUSED-LITERAL-0123456789-ABCDEFGHIJ-0123456789';
      const used = 'INV-USED-LITERAL-0123456789-ABCDEFGHIJ-0123456789';
      const note =
          'Literal long note 保留原文: customer supplied details remain unchanged across interface languages.';
      const user = 'Literal user with a long account name 保留原文';
      fixture.codes
        ..clear()
        ..addAll([
          {..._inviteFixtureItem(unused), 'note': note},
          {
            ..._inviteFixtureItem(used),
            'note': note,
            'used_by': 'literal-user',
            'used_by_name': user,
            'used_at': '2026-10-02 08:00:00',
          },
        ]);
      await tester.tap(_refreshButton());
      await tester.pumpAndSettle();
      for (final locale in [AppLocale.zh, AppLocale.en]) {
        I18n.setLocale(locale);
        await tester.pumpAndSettle();
        for (final status in ['unused', 'used']) {
          await _tapStatusChip(tester, status);
          final code = find.text(status == 'unused' ? unused : used);
          await tester.scrollUntilVisible(
            code,
            120,
            scrollable: _inviteListScrollable(),
            maxScrolls: 30,
          );
          await Scrollable.ensureVisible(tester.element(code), alignment: 0);
          await tester.pumpAndSettle();
          expect(find.text(note), findsOneWidget);
          expect(tester.getRect(code).left, greaterThanOrEqualTo(0));
          expect(tester.getRect(code).right, lessThanOrEqualTo(320));
          if (status == 'used') {
            expect(
              find.text(
                '${locale == AppLocale.zh ? '使用者：' : 'Used by: '}$user',
              ),
              findsOneWidget,
            );
            expect(_deleteButton(), findsNothing);
          } else {
            expect(_deleteButton(), findsOneWidget);
          }
          await _captureIfRequested(
            tester,
            fixture,
            'invites-320-long-2_0-${locale == AppLocale.zh ? 'zh' : 'en'}-$status',
          );
          expect(tester.takeException(), isNull);
        }
      }
      expect(fixture.inviteMutations, isEmpty);
    },
  );

  testWidgets(
    'Generation note and actions remain reachable with keyboard and live locale',
    (tester) async {
      final fixture = await _mountInvites(
        tester,
        width: 320,
        height: 640,
        textScale: 1.6,
      );
      await _openGenerationDialog(tester);
      final route = fixture.routes.current;
      await tester.enterText(_noteField(), _generatedNote);
      final controller = tester.widget<TextField>(_noteField()).controller!;
      tester.view.viewInsets = const FakeViewPadding(bottom: 200);
      await tester.pumpAndSettle();
      for (final locale in [AppLocale.zh, AppLocale.en]) {
        I18n.setLocale(locale);
        await tester.pumpAndSettle();
        expect(fixture.routes.current, same(route));
        expect(
          tester.widget<TextField>(_noteField()).controller,
          same(controller),
        );
        expect(controller.text, _generatedNote);
        await tester.ensureVisible(_noteField());
        final fieldRect = tester.getRect(_noteField());
        expect(fieldRect.top, greaterThanOrEqualTo(0));
        expect(fieldRect.bottom, lessThanOrEqualTo(440));
        for (final action in [_dialogPrimaryButton(), _dialogCancelButton()]) {
          expect(action.hitTestable(), findsOneWidget);
          final rect = tester.getRect(action);
          expect(rect.top, greaterThanOrEqualTo(0));
          expect(rect.bottom, lessThanOrEqualTo(440));
        }
        await _captureIfRequested(
          tester,
          fixture,
          'invites-320-keyboard-1_6-${locale == AppLocale.zh ? 'zh' : 'en'}',
        );
        expect(tester.takeException(), isNull);
      }
      await _tapDialogAction(tester, '取消', 'Cancel');
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      await _openGenerationDialog(tester);
      expect(tester.widget<TextField>(_noteField()).controller!.text, isEmpty);
      await _tapDialogAction(tester, '取消', 'Cancel');
      expect(fixture.inviteMutations, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Generate button submits bounded quantity and exact note once; code text survives locale changes',
    (tester) async {
      final clipboardWrites = _installClipboardSpy(tester);
      final fixture = await _mountInvites(tester);

      for (final count in [1, 50]) {
        await _openGenerationDialog(tester);
        final slider = tester.widget<Slider>(
          find.byKey(const ValueKey('admin_invites_count_slider')),
        );
        expect(slider.min, 1);
        expect(slider.max, 50);
        expect(slider.divisions, 49);
        slider.onChanged!(count.toDouble());
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<Slider>(
                find.byKey(const ValueKey('admin_invites_count_slider')),
              )
              .value,
          count.toDouble(),
        );
        await tester.enterText(
          find.byKey(const ValueKey('admin_invites_note_field')),
          _generatedNote,
        );

        final writesBefore = fixture.inviteMutations.length;
        if (count == 50) {
          final submit = _dialogPrimaryCallback(tester);
          submit();
          submit(); // A retained confirmation callback must be single-use.
        } else {
          await tester.tap(_dialogPrimaryButton());
        }
        await tester.pumpAndSettle();
        expect(fixture.inviteMutations, hasLength(writesBefore + 1));
        final request = fixture.inviteMutations.last;
        expect(request.method, 'POST');
        expect(request.path, '/api/admin/invite-codes');
        expect(fixture.mutationBodies.last, {
          'count': count,
          'note': _generatedNote,
        });

        final codes = fixture.generatedBatches.last;
        expect(codes, hasLength(count));
        _expectResultDialog(tester, AppLocale.zh, codes);
        I18n.setLocale(AppLocale.en);
        await tester.pumpAndSettle();
        _expectResultDialog(tester, AppLocale.en, codes);
        expect(
          tester
              .widget<SelectableText>(
                find.byKey(const ValueKey('admin_invites_generated_codes')),
              )
              .data,
          codes.join('\n'),
        );
        await _tapDialogAction(tester, '复制并关闭', 'Copy and close');
        expect(clipboardWrites.last, codes.join('\n'));
        I18n.setLocale(AppLocale.zh);
        await tester.pumpAndSettle();
      }

      expect(fixture.inviteMutations, hasLength(2));
      expect(fixture.inviteReads, hasLength(3));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Cancelled generation dialog disposes its draft and stale actions cannot affect a reopened dialog',
    (tester) async {
      final fixture = await _mountInvites(tester);
      await _openGenerationDialog(tester);
      final cancelledRoute = fixture.routes.current;
      final sliderFinder = find.byKey(
        const ValueKey('admin_invites_count_slider'),
      );
      tester.widget<Slider>(sliderFinder).onChanged!(17);
      await tester.pumpAndSettle();

      final noteField = _noteField();
      await tester.enterText(noteField, _generatedNote);
      final cancelledController = tester
          .widget<TextField>(noteField)
          .controller!;
      cancelledController.selection = const TextSelection(
        baseOffset: 1,
        extentOffset: 9,
      );
      final cancelledSelection = cancelledController.selection;
      final cancelledFocusNode = tester
          .widget<EditableText>(
            find.descendant(of: noteField, matching: find.byType(EditableText)),
          )
          .focusNode;
      expect(FocusManager.instance.primaryFocus, same(cancelledFocusNode));
      final staleSubmit = _dialogPrimaryCallback(tester);
      final cancelButton = find.widgetWithText(TextButton, '取消');
      final staleCancel = tester.widget<TextButton>(cancelButton).onPressed!;
      final readsBeforeLocaleChanges = List<String>.of(fixture.requestLines);

      for (final locale in [AppLocale.en, AppLocale.zh]) {
        I18n.setLocale(locale);
        await tester.pumpAndSettle();
        expect(fixture.routes.current, same(cancelledRoute));
        expect(tester.widget<Slider>(sliderFinder).value, 17.0);
        expect(
          tester.widget<TextField>(_noteField()).controller,
          same(cancelledController),
        );
        expect(cancelledController.text, _generatedNote);
        expect(cancelledController.selection, cancelledSelection);
        expect(FocusManager.instance.primaryFocus, same(cancelledFocusNode));
        _expectGenerationDialog(tester, locale);
        expect(fixture.requestLines, readsBeforeLocaleChanges);
      }

      await _tapDialogAction(tester, '取消', 'Cancel');
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(() => cancelledController.addListener(() {}), throwsFlutterError);

      await _openGenerationDialog(tester);
      final reopenedRoute = fixture.routes.current;
      staleSubmit();
      staleCancel();
      await tester.pumpAndSettle();
      expect(fixture.routes.current, same(reopenedRoute));
      expect(find.byType(Dialog), findsOneWidget);
      expect(tester.widget<Slider>(sliderFinder).value, 5.0);
      expect(
        tester.widget<TextField>(_noteField()).controller,
        isNot(same(cancelledController)),
      );
      expect(tester.widget<TextField>(_noteField()).controller!.text, isEmpty);
      expect(fixture.inviteMutations, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Successful generation remains visible when its list refresh fails and refresh can retry alone',
    (tester) async {
      final fixture = await _mountInvites(tester);
      fixture.failNextInviteRead(
        _jsonResponse({
          'detail': 'synthetic invite refresh failure',
        }, status: 500),
      );

      final codes = await _generateAndShowResult(
        tester,
        fixture,
        count: 3,
        note: _generatedNote,
      );
      expect(fixture.inviteMutations, hasLength(1));
      expect(fixture.inviteMutations.single.method, 'POST');
      expect(fixture.inviteReads, hasLength(2));
      expect(
        tester
            .widget<SelectableText>(
              find.byKey(const ValueKey('admin_invites_generated_codes')),
            )
            .data,
        codes.join('\n'),
      );
      expect(find.text('邀请码已生成，但列表刷新失败。请保存这些邀请码，再刷新列表。'), findsOneWidget);

      await _tapDialogAction(tester, '关闭', 'Close');
      await tester.pumpAndSettle();
      await tester.tap(_refreshButton());
      await tester.pumpAndSettle();
      expect(fixture.inviteMutations, hasLength(1));
      expect(fixture.inviteReads, hasLength(3));
      for (final code in codes) {
        expect(find.text(code), findsOneWidget);
      }
      expect(find.text('邀请码已生成，但列表刷新失败。请保存这些邀请码，再刷新列表。'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Covered first invite read retries on return without showing a false empty state',
    (tester) async {
      final fixture = await _mountInvites(tester, holdInitialInviteRead: true);
      final heldInitialRead = fixture.initialHeldInviteRead!;
      expect(fixture.inviteReads, hasLength(1));
      expect(find.text(_unusedCode), findsNothing);
      expect(tester.widget<FilledButton>(_generateButton()).onPressed, isNull);

      await tester.tap(find.byIcon(Icons.grid_view_outlined));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final moduleMenuRoute = fixture.routes.current;
      expect(moduleMenuRoute, isNotNull);
      expect(find.byType(PopupMenuItem<int>), findsWidgets);
      expect(find.byType(Dialog), findsNothing);

      fixture.codes
        ..clear()
        ..add(_inviteFixtureItem('INV-FIRST-GET-RECOVERED'));
      heldInitialRead.complete(
        _inviteCodesResponse([_inviteFixtureItem('INV-FIRST-GET-COVERED')]),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(fixture.inviteReads, hasLength(1));
      expect(find.text('INV-FIRST-GET-COVERED'), findsNothing);
      expect(find.text('INV-FIRST-GET-RECOVERED'), findsNothing);
      expect(find.text('暂无邀请码，可生成邀请码供新用户注册'), findsNothing);

      await tester.tap(find.byType(PopupMenuItem<int>).at(8));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(fixture.routes.current, isNot(same(moduleMenuRoute)));
      expect(find.byType(Dialog), findsNothing);
      await tester.pumpAndSettle();

      expect(fixture.inviteReads, hasLength(2));
      expect(fixture.inviteReads.last.queryParameters, {
        'sort': 'created_desc',
        'limit': '20',
        'offset': '0',
      });
      expect(find.text('INV-FIRST-GET-RECOVERED'), findsOneWidget);
      expect(find.text('INV-FIRST-GET-COVERED'), findsNothing);
      expect(find.text('暂无邀请码，可生成邀请码供新用户注册'), findsNothing);
      expect(fixture.inviteMutations, isEmpty);
      expect(
        tester.widget<FilledButton>(_generateButton()).onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Same-account client replacement rejects a held old invite read and resets sort',
    (tester) async {
      final fixture = await _mountInvites(tester);
      final createdSort = find.descendant(
        of: _inviteModule(),
        matching: find.text('最新生成优先'),
      );
      await tester.ensureVisible(createdSort);
      await tester.tap(createdSort);
      await tester.pumpAndSettle();
      await tester.tap(find.text('邀请码 A-Z'));
      await tester.pumpAndSettle();
      expect(fixture.inviteReads.last.queryParameters['sort'], 'code_asc');
      expect(_inviteSortValue(tester), 'code_asc');

      // The unified list lazily builds its children. Return to the opener
      // before capturing its enabled callback for the held refresh.
      final inviteScrollable = tester.state<ScrollableState>(
        _elementFinder(_scrollableWithContent(tester, _inviteModule())),
      );
      inviteScrollable.position.jumpTo(0);
      await tester.pumpAndSettle();
      final heldOldRead = fixture.holdNextInviteRead();
      final retainedGenerateWhileLoading = _generateButtonCallback(tester);
      await tester.tap(_refreshButton());
      await tester.pump();
      expect(fixture.inviteReads.last.queryParameters['sort'], 'code_asc');
      final requestsWhileLoading = List<String>.of(fixture.requestLines);
      retainedGenerateWhileLoading();
      await tester.pump();
      expect(find.byType(Dialog), findsNothing);
      expect(fixture.inviteMutations, isEmpty);
      expect(fixture.requestLines, requestsWhileLoading);

      fixture.codes
        ..clear()
        ..add(_inviteFixtureItem('INV-NEW-CLIENT-RESULT'));
      fixture.replaceClient(
        fixture.newClient(token: fixture.client.token ?? ''),
      );
      await tester.pumpAndSettle();
      expect(fixture.inviteReads.last.queryParameters, {
        'sort': 'created_desc',
        'limit': '20',
        'offset': '0',
      });
      expect(_inviteSortValue(tester), 'created_desc');
      expect(find.text('最新生成优先'), findsOneWidget);
      expect(find.text('邀请码 A-Z'), findsNothing);
      expect(find.text('INV-NEW-CLIENT-RESULT'), findsOneWidget);

      heldOldRead.complete(
        _inviteCodesResponse([_inviteFixtureItem('INV-OLD-CLIENT-RESULT')]),
      );
      await tester.pumpAndSettle();
      expect(find.text('INV-NEW-CLIENT-RESULT'), findsOneWidget);
      expect(find.text('INV-OLD-CLIENT-RESULT'), findsNothing);
      expect(fixture.inviteReads, hasLength(4));

      await tester.tap(find.text('最新生成优先'));
      await tester.pumpAndSettle();
      final sortMenuRoute = fixture.routes.current;
      final pushedBeforeLocaleChange = fixture.routes.pushed.length;
      final readsBeforeLocaleChange = List<String>.of(fixture.requestLines);
      expect(find.text('邀请码 A-Z'), findsOneWidget);
      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      expect(fixture.routes.current, same(sortMenuRoute));
      expect(fixture.routes.pushed, hasLength(pushedBeforeLocaleChange));
      expect(find.text('Code A–Z'), findsOneWidget);
      expect(_inviteSortValue(tester), 'created_desc');
      expect(fixture.requestLines, readsBeforeLocaleChange);
      expect(tester.takeException(), isNull);

      fixture.navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(fixture.requestLines, readsBeforeLocaleChange);
    },
  );

  testWidgets(
    'Closing stale generation confirmation after client replacement restores usable invite actions',
    (tester) async {
      final fixture = await _mountInvites(tester);
      const recoveredCode = 'INV-CLIENT-CONFIRM-RECOVERED';
      fixture.codes
        ..clear()
        ..add(_inviteFixtureItem(recoveredCode));

      await _openGenerationDialog(tester);
      final oldDialogRoute = fixture.routes.current;
      final staleSubmit = _dialogPrimaryCallback(tester);
      fixture.replaceClient(
        fixture.newClient(token: fixture.client.token ?? ''),
      );
      await tester.pumpAndSettle();
      expect(fixture.inviteReads, hasLength(1));
      staleSubmit();
      await tester.pumpAndSettle();
      expect(fixture.routes.current, same(oldDialogRoute));
      expect(find.byType(Dialog), findsOneWidget);
      expect(fixture.inviteMutations, isEmpty);

      fixture.navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(fixture.inviteReads, hasLength(2));
      expect(find.text(recoveredCode), findsOneWidget);

      final generatedCodes = await _generateAndShowResult(
        tester,
        fixture,
        count: 1,
        note: 'replacement client note',
      );
      expect(generatedCodes, hasLength(1));
      expect(fixture.inviteMutations.map((request) => request.method), [
        'POST',
      ]);
      await _tapDialogAction(tester, '关闭', 'Close');
      await tester.pumpAndSettle();

      await _openDeleteDialog(tester);
      _expectDeleteDialog(tester, AppLocale.zh, generatedCodes.single);
      await tester.tap(_dialogPrimaryButton());
      await tester.pumpAndSettle();
      expect(fixture.inviteMutations.map((request) => request.method), [
        'POST',
        'DELETE',
      ]);
      expect(
        fixture.inviteMutations.last.path,
        '/api/admin/invite-codes/${generatedCodes.single}',
      );
      expect(fixture.inviteReads, hasLength(4));
      expect(find.text(recoveredCode), findsOneWidget);
      expect(find.text(generatedCodes.single), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Finishing an old client generation cannot release the new client pending mutation',
    (tester) async {
      final fixture = await _mountInvites(tester);

      final heldOldPost = fixture.holdNextMutation();
      await _openGenerationDialog(tester);
      await tester.enterText(_noteField(), 'old client note');
      await tester.tap(_dialogPrimaryButton());
      await tester.pumpAndSettle();
      expect(fixture.inviteMutations, hasLength(1));

      fixture.replaceClient(
        fixture.newClient(token: fixture.client.token ?? ''),
      );
      await tester.pumpAndSettle();
      expect(fixture.inviteReads, hasLength(2));

      final heldNewPost = fixture.holdNextMutation();
      await _openGenerationDialog(tester);
      await tester.enterText(_noteField(), 'new client note');
      await tester.tap(_dialogPrimaryButton());
      await tester.pumpAndSettle();
      expect(fixture.inviteMutations, hasLength(2));

      heldOldPost.complete(
        _jsonResponse({
          'codes': ['INV-OLD-CLIENT-MUTATION'],
        }),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('INV-OLD-CLIENT-MUTATION'), findsNothing);
      expect(tester.widget<FilledButton>(_generateButton()).onPressed, isNull);
      expect(fixture.inviteMutations, hasLength(2));
      expect(fixture.inviteReads, hasLength(2));

      heldNewPost.complete(
        _jsonResponse({
          'codes': ['INV-NEW-CLIENT-MUTATION'],
        }),
      );
      await tester.pumpAndSettle();
      _expectResultDialog(tester, AppLocale.zh, ['INV-NEW-CLIENT-MUTATION']);
      expect(
        tester
            .widget<SelectableText>(
              find.byKey(const ValueKey('admin_invites_generated_codes')),
            )
            .data,
        'INV-NEW-CLIENT-MUTATION',
      );
      await _tapDialogAction(tester, '关闭', 'Close');
      await tester.pumpAndSettle();
      expect(fixture.inviteMutations, hasLength(2));
      expect(fixture.inviteReads, hasLength(3));
      expect(
        tester.widget<FilledButton>(_generateButton()).onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Retained generation and delete openers reject account, client, token, and permission changes',
    (tester) async {
      for (final boundary in const [
        'account replacement',
        'client replacement',
        'token rotation',
        'permission revoke and re-grant',
      ]) {
        final fixture = await _mountInvites(tester);
        final retainedGenerate = _generateButtonCallback(tester);
        final retainedDelete = _deleteButtonCallback(tester);
        await _invalidateAuthority(tester, fixture, boundary);
        final requestsAfterBoundary = List<String>.of(fixture.requestLines);

        retainedGenerate();
        retainedDelete();
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing, reason: boundary);
        expect(fixture.inviteMutations, isEmpty, reason: boundary);
        expect(fixture.requestLines, requestsAfterBoundary, reason: boundary);
        expect(tester.takeException(), isNull, reason: boundary);
      }
    },
  );

  testWidgets(
    'Held generation and delete confirmations reject every changed authority boundary',
    (tester) async {
      for (final boundary in const [
        'account replacement',
        'client replacement',
        'token rotation',
        'permission revoke and re-grant',
      ]) {
        final fixture = await _mountInvites(tester);
        const recoveredCode = 'INV-CLIENT-GENERATION-RECOVERED';
        if (boundary == 'client replacement') {
          fixture.codes
            ..clear()
            ..add(_inviteFixtureItem(recoveredCode));
        }

        await _openGenerationDialog(tester);
        final generationRoute = fixture.routes.current;
        final staleGenerateConfirm = _dialogPrimaryCallback(tester);
        await _invalidateAuthority(tester, fixture, boundary);
        final afterGenerationBoundary = List<String>.of(fixture.requestLines);
        staleGenerateConfirm();
        await tester.pumpAndSettle();
        expect(fixture.inviteMutations, isEmpty, reason: boundary);
        expect(fixture.requestLines, afterGenerationBoundary, reason: boundary);
        expect(fixture.routes.current, same(generationRoute), reason: boundary);
        expect(find.byType(Dialog), findsOneWidget, reason: boundary);
        if (boundary == 'client replacement') {
          expect(fixture.inviteReads, hasLength(1));
        }
        fixture.navigatorKey.currentState!.pop();
        await tester.pumpAndSettle();
        if (boundary == 'client replacement') {
          expect(fixture.inviteReads, hasLength(2));
          expect(find.text(recoveredCode), findsOneWidget);
          final recoveredGenerate = _generateButtonCallback(tester);
          recoveredGenerate();
          await tester.pumpAndSettle();
          expect(find.byType(Dialog), findsOneWidget);
          await _tapDialogAction(tester, '取消', 'Cancel');
          await _openDeleteDialog(tester);
          _expectDeleteDialog(tester, AppLocale.zh, recoveredCode);
          await _tapDialogAction(tester, '取消', 'Cancel');
          expect(fixture.inviteMutations, isEmpty);
        }

        fixture.replaceAuth(
          _switchableAuth(
            fixture.client,
            _adminState(token: fixture.client.token ?? ''),
          ),
        );
        await tester.pumpAndSettle();
        const deleteRecoveryCode = 'INV-CLIENT-DELETE-RECOVERED';
        if (boundary == 'client replacement') {
          fixture.codes
            ..clear()
            ..add(_inviteFixtureItem(deleteRecoveryCode));
        }
        await _openDeleteDialog(tester);
        final deleteRoute = fixture.routes.current;
        final readsBeforeDeleteBoundary = fixture.inviteReads.length;
        final staleDeleteConfirm = _dialogPrimaryCallback(tester);
        await _invalidateAuthority(tester, fixture, boundary);
        final afterDeleteBoundary = List<String>.of(fixture.requestLines);
        staleDeleteConfirm();
        await tester.pumpAndSettle();
        expect(fixture.inviteMutations, isEmpty, reason: boundary);
        expect(fixture.requestLines, afterDeleteBoundary, reason: boundary);
        expect(fixture.routes.current, same(deleteRoute), reason: boundary);
        expect(find.byType(Dialog), findsOneWidget, reason: boundary);
        if (boundary == 'client replacement') {
          expect(fixture.inviteReads, hasLength(readsBeforeDeleteBoundary));
          fixture.navigatorKey.currentState!.pop();
          await tester.pumpAndSettle();
          expect(fixture.inviteReads, hasLength(readsBeforeDeleteBoundary + 1));
          expect(find.text(deleteRecoveryCode), findsOneWidget);
          await _openDeleteDialog(tester);
          _expectDeleteDialog(tester, AppLocale.zh, deleteRecoveryCode);
          await _tapDialogAction(tester, '取消', 'Cancel');
          expect(fixture.inviteMutations, isEmpty);
        }
        expect(tester.takeException(), isNull, reason: boundary);
      }
    },
  );

  testWidgets(
    'Tab leave-return and same-frame animateTo invalidate captured Invites actions',
    (tester) async {
      final fixture = await _mountInvites(tester);
      final beforeLeaveGenerate = _generateButtonCallback(tester);
      final beforeLeaveDelete = _deleteButtonCallback(tester);

      await _selectAdminTab(tester, '日志', 'Logs');
      await _selectAdminTab(tester, '邀请码', 'Invites');
      final requestsAfterReturn = List<String>.of(fixture.requestLines);
      beforeLeaveGenerate();
      beforeLeaveDelete();
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(fixture.inviteMutations, isEmpty);
      expect(fixture.requestLines, requestsAfterReturn);

      final tabController = tester
          .widget<TabBar>(find.byType(TabBar))
          .controller!;
      final sameFrameGenerate = _generateButtonCallback(tester);
      final sameFrameDelete = _deleteButtonCallback(tester);
      tabController.animateTo(9);
      tabController.animateTo(8);
      sameFrameGenerate();
      sameFrameDelete();
      await tester.pumpAndSettle();
      expect(tabController.index, 8);
      expect(find.byType(Dialog), findsNothing);
      expect(fixture.inviteMutations, isEmpty);

      final currentGenerate = _generateButtonCallback(tester);
      currentGenerate();
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      await _tapDialogAction(tester, '取消', 'Cancel');
      await _openDeleteDialog(tester);
      await _tapDialogAction(tester, '取消', 'Cancel');
      expect(fixture.inviteMutations, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Pending generation and deletion responses do not reload or show stale feedback',
    (tester) async {
      for (final boundary in const [
        'account replacement',
        'client replacement',
        'token rotation',
        'permission revoke and re-grant',
      ]) {
        final fixture = await _mountInvites(tester);
        await _openGenerationDialog(tester);
        await tester.enterText(
          find.byKey(const ValueKey('admin_invites_note_field')),
          _generatedNote,
        );
        final heldPost = fixture.holdNextMutation();
        await tester.tap(_dialogPrimaryButton());
        await tester.pumpAndSettle();
        expect(fixture.inviteMutations, hasLength(1), reason: boundary);
        expect(fixture.inviteMutations.single.method, 'POST');
        await _invalidateAuthority(tester, fixture, boundary);
        final readsAfterGenerationBoundary = fixture.inviteReads
            .map((request) => request.line)
            .toList();
        final codes = ['INV-STALE-RESPONSE'];
        heldPost.complete(_jsonResponse({'codes': codes}));
        await tester.pumpAndSettle();
        expect(
          fixture.inviteReads.map((request) => request.line).toList(),
          readsAfterGenerationBoundary,
          reason: boundary,
        );
        expect(find.textContaining('INV-STALE-RESPONSE'), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
        expect(fixture.inviteMutations, hasLength(1));
        expect(tester.takeException(), isNull, reason: boundary);
      }

      for (final boundary in const [
        'account replacement',
        'client replacement',
        'token rotation',
        'permission revoke and re-grant',
      ]) {
        final fixture = await _mountInvites(tester);
        await _openDeleteDialog(tester);
        final heldDelete = fixture.holdNextMutation();
        await tester.tap(_dialogPrimaryButton());
        await tester.pumpAndSettle();
        expect(fixture.inviteMutations, hasLength(1), reason: boundary);
        expect(fixture.inviteMutations.single.method, 'DELETE');
        expect(
          fixture.inviteMutations.single.path,
          '/api/admin/invite-codes/$_unusedCode',
        );
        await _invalidateAuthority(tester, fixture, boundary);
        final readsAfterDeleteBoundary = fixture.inviteReads
            .map((request) => request.line)
            .toList();
        heldDelete.complete(_jsonResponse({}));
        await tester.pumpAndSettle();
        expect(
          fixture.inviteReads.map((request) => request.line).toList(),
          readsAfterDeleteBoundary,
          reason: boundary,
        );
        expect(find.byType(SnackBar), findsNothing);
        expect(fixture.inviteMutations, hasLength(1));
        expect(tester.takeException(), isNull, reason: boundary);
      }
    },
  );

  testWidgets(
    'Result copy callback cannot copy or pop after account change or route coverage',
    (tester) async {
      final clipboardWrites = _installClipboardSpy(tester);
      final fixture = await _mountInvites(tester);
      final codes = await _generateAndShowResult(
        tester,
        fixture,
        count: 2,
        note: _generatedNote,
      );
      final copy = _copyAndCloseCallback(tester);
      fixture.replaceAuth(
        _switchableAuth(
          fixture.client,
          _adminState(
            userId: 'replacement-invite-admin',
            token: fixture.client.token ?? '',
          ),
        ),
      );
      await tester.pumpAndSettle();
      final routeAfterAccountChange = fixture.routes.current;
      final currentReads = fixture.inviteReads
          .map((request) => request.line)
          .toList();
      copy();
      await tester.pumpAndSettle();
      expect(clipboardWrites, isEmpty);
      expect(fixture.routes.current, same(routeAfterAccountChange));
      expect(
        fixture.inviteReads.map((request) => request.line).toList(),
        currentReads,
      );

      final coveringRoute = MaterialPageRoute<void>(
        builder: (_) =>
            const Scaffold(body: Center(child: Text('covering invite route'))),
      );
      unawaited(fixture.navigatorKey.currentState!.push<void>(coveringRoute));
      await tester.pumpAndSettle();
      copy();
      await tester.pumpAndSettle();
      expect(find.text('covering invite route'), findsOneWidget);
      expect(fixture.routes.current, same(coveringRoute));
      expect(clipboardWrites, isEmpty);
      expect(fixture.inviteMutations, hasLength(1));
      expect(codes, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Closing a result dialog after same-account client replacement reloads the new client list',
    (tester) async {
      final clipboardWrites = _installClipboardSpy(tester);
      final fixture = await _mountInvites(tester);
      final oldCodes = await _generateAndShowResult(
        tester,
        fixture,
        count: 2,
        note: _generatedNote,
      );
      final staleCopy = _copyAndCloseCallback(tester);
      final resultRoute = fixture.routes.current;
      const recoveredCode = 'INV-CLIENT-RESULT-RECOVERED';
      fixture.codes
        ..clear()
        ..add(_inviteFixtureItem(recoveredCode));
      fixture.replaceClient(
        fixture.newClient(token: fixture.client.token ?? ''),
      );
      await tester.pumpAndSettle();
      expect(fixture.inviteReads, hasLength(2));
      staleCopy();
      await tester.pumpAndSettle();
      expect(clipboardWrites, isEmpty);
      expect(fixture.routes.current, same(resultRoute));

      await _tapDialogAction(tester, '关闭', 'Close');
      await tester.pumpAndSettle();
      expect(fixture.inviteReads, hasLength(3));
      expect(fixture.inviteReads.last.queryParameters['sort'], 'created_desc');
      expect(find.text(recoveredCode), findsOneWidget);
      for (final oldCode in oldCodes) {
        expect(find.text(oldCode), findsNothing);
      }

      final replacementCodes = await _generateAndShowResult(
        tester,
        fixture,
        count: 1,
        note: 'replacement result note',
      );
      expect(fixture.inviteMutations.map((request) => request.method), [
        'POST',
        'POST',
      ]);
      await _tapDialogAction(tester, '关闭', 'Close');
      await tester.pumpAndSettle();
      await _openDeleteDialog(tester);
      _expectDeleteDialog(tester, AppLocale.zh, replacementCodes.single);
      await tester.tap(_dialogPrimaryButton());
      await tester.pumpAndSettle();
      expect(fixture.inviteMutations.map((request) => request.method), [
        'POST',
        'POST',
        'DELETE',
      ]);
      expect(fixture.inviteReads, hasLength(5));
      expect(find.text(recoveredCode), findsOneWidget);
      expect(find.text(replacementCodes.single), findsNothing);
      expect(clipboardWrites, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Held clipboard completion preserves a covered result route and restores copy on return',
    (tester) async {
      final firstClipboardWrite = Completer<void>();
      final clipboardWrites = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            final arguments = call.arguments as Map<Object?, Object?>;
            clipboardWrites.add(arguments['text'] as String);
            if (clipboardWrites.length == 1) await firstClipboardWrite.future;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      final fixture = await _mountInvites(tester);
      final codes = await _generateAndShowResult(
        tester,
        fixture,
        count: 2,
        note: _generatedNote,
      );
      final resultRoute = fixture.routes.current;
      final copyAction = _copyAndCloseActionButton();
      await tester.tap(copyAction);
      await tester.pump();
      expect(clipboardWrites, [codes.join('\n')]);
      expect(tester.widget<FilledButton>(copyAction).onPressed, isNull);

      final coveringRoute = MaterialPageRoute<void>(
        builder: (_) => const Scaffold(
          body: Center(child: Text('covering held-copy route')),
        ),
      );
      unawaited(fixture.navigatorKey.currentState!.push<void>(coveringRoute));
      await tester.pumpAndSettle();
      expect(fixture.routes.current, same(coveringRoute));

      firstClipboardWrite.complete();
      await tester.pumpAndSettle();
      expect(fixture.routes.current, same(coveringRoute));
      expect(find.text('covering held-copy route'), findsOneWidget);

      fixture.navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(fixture.routes.current, same(resultRoute));
      final returnedCopyAction = _copyAndCloseActionButton();
      expect(
        tester.widget<FilledButton>(returnedCopyAction).onPressed,
        isNotNull,
      );
      await tester.tap(returnedCopyAction);
      await tester.pumpAndSettle();
      expect(clipboardWrites, [codes.join('\n'), codes.join('\n')]);
      expect(fixture.routes.current, isNot(same(resultRoute)));
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Delete API failure keeps the code and exposes retry feedback', (
    tester,
  ) async {
    final fixture = await _mountInvites(tester);
    final heldFailure = fixture.holdNextMutation();
    await _openDeleteDialog(tester);
    final deleteConfirm = _dialogPrimaryCallback(tester);
    deleteConfirm();
    deleteConfirm(); // A retained confirmation callback must be single-use.
    await tester.pumpAndSettle();
    expect(fixture.inviteMutations, hasLength(1));
    expect(fixture.inviteMutations.single.method, 'DELETE');
    expect(
      fixture.inviteMutations.single.path,
      '/api/admin/invite-codes/$_unusedCode',
    );

    I18n.setLocale(AppLocale.en);
    await tester.pumpAndSettle();
    heldFailure.complete(
      _jsonResponse({'detail': _deleteFailure}, status: 500),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text(_unusedCode), findsOneWidget);
    expect(fixture.inviteReads, hasLength(1));
    expect(
      tester.widget<IconButton>(_deleteButton().first).onPressed,
      isNotNull,
    );
    // A deliberate retry uses a fresh confirmation rather than replaying the
    // failed destructive request through an obsolete callback.
    await _openDeleteDialog(tester);
    _expectDeleteDialog(tester, AppLocale.en, _unusedCode);
    await tester.tap(_dialogPrimaryButton());
    await tester.pumpAndSettle();

    expect(fixture.inviteMutations, hasLength(2));
    expect(fixture.inviteMutations.last.method, 'DELETE');
    expect(fixture.inviteReads, hasLength(2));
    expect(find.text(_unusedCode), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

String _localeText(String zh, String en, [AppLocale? locale]) =>
    (locale ?? I18n.current) == AppLocale.zh ? zh : en;

Future<_InvitesFixture> _mountInvites(
  WidgetTester tester, {
  double width = 390,
  double height = 900,
  double textScale = 1,
  int codeCount = 5,
  bool holdInitialInviteRead = false,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.runAsync(loadWidgetPolishScreenshotFonts);
  final fixture = _InvitesFixture(codeCount: codeCount);
  if (holdInitialInviteRead) {
    fixture.initialHeldInviteRead = fixture.holdNextInviteRead();
  }
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
            home: const AdminScreen(initialTabIndex: 8),
          ),
        );
      },
    ),
  );
  fixture.rebuildHost = rebuildHost;
  if (holdInitialInviteRead) {
    await tester.pump();
  } else {
    await tester.pumpAndSettle();
  }
  expect(_inviteModule(), findsOneWidget);
  expect(fixture.inviteReads, hasLength(1));
  expect(tester.takeException(), isNull);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
  });
  return fixture;
}

Future<void> _openGenerationDialog(WidgetTester tester) async {
  await _returnToInviteHeader(tester);
  final button = _generateButton();
  expect(button, findsOneWidget);
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
  expect(find.byType(Dialog), findsOneWidget);
}

Future<void> _openDeleteDialog(WidgetTester tester) async {
  final button = _deleteButton();
  await tester.scrollUntilVisible(
    button.first,
    160,
    scrollable: _inviteListScrollable(),
    maxScrolls: 30,
  );
  await tester.tap(button.first);
  await tester.pumpAndSettle();
  expect(find.byType(Dialog), findsOneWidget);
}

Future<void> _tapStatusChip(WidgetTester tester, String status) async {
  await _returnToInviteHeader(tester);
  final label = status == 'unused'
      ? _localeText('未使用', 'Unused')
      : _localeText('已使用', 'Used');
  final chip = find.widgetWithText(ChoiceChip, label);
  expect(chip, findsOneWidget);
  await tester.ensureVisible(chip);
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

Future<void> _selectAdminTab(WidgetTester tester, String zh, String en) async {
  final title = _localeText(zh, en);
  final tab = find.descendant(
    of: find.byType(TabBar),
    matching: find.text(title),
  );
  expect(tab, findsOneWidget);
  await tester.ensureVisible(tab);
  await tester.tap(tab);
  await tester.pumpAndSettle();
}

Finder _generateButton() =>
    find.byKey(const ValueKey('admin_invites_generate_button'));

Finder _inviteListScrollable() => find
    .descendant(
      of: find.descendant(of: _inviteModule(), matching: find.byType(ListView)),
      matching: find.byType(Scrollable),
    )
    .first;

Future<void> _returnToInviteHeader(WidgetTester tester) async {
  tester.state<ScrollableState>(_inviteListScrollable()).position.jumpTo(0);
  await tester.pumpAndSettle();
}

Finder _searchField(WidgetTester tester) => find
    .descendant(of: _inviteModule(), matching: find.byType(TextField))
    .first;

Finder _inviteSortFormField() {
  final label = find.descendant(
    of: _inviteModule(),
    matching: find.text(_localeText('邀请码排序', 'Sort invite codes')),
  );
  expect(label, findsOneWidget);
  final field = find.ancestor(
    of: label,
    matching: find.byType(FormField<String>),
  );
  expect(field, findsOneWidget);
  return field;
}

String? _inviteSortValue(WidgetTester tester) =>
    tester.widget<FormField<String>>(_inviteSortFormField()).initialValue;

Finder _refreshButton() => find.descendant(
  of: _inviteModule(),
  matching: find.text(_localeText('刷新', 'Refresh')),
);

Finder _deleteButton() => find.byWidgetPredicate(
  (widget) =>
      widget is IconButton &&
      widget.tooltip == _localeText('删除邀请码', 'Delete invite code'),
);

VoidCallback _generateButtonCallback(WidgetTester tester) {
  final button = _generateButton();
  expect(button, findsOneWidget);
  return tester.widget<FilledButton>(button).onPressed!;
}

VoidCallback _deleteButtonCallback(WidgetTester tester) {
  final button = _deleteButton();
  expect(button, findsWidgets);
  return tester.widget<IconButton>(button.first).onPressed!;
}

Finder _dialogPrimaryButton() {
  final buttons = find.descendant(
    of: find.byType(Dialog),
    matching: find.byType(FilledButton),
  );
  expect(buttons, findsWidgets);
  return buttons.last;
}

VoidCallback _dialogPrimaryCallback(WidgetTester tester) =>
    tester.widget<FilledButton>(_dialogPrimaryButton()).onPressed!;

Future<void> _tapDialogAction(WidgetTester tester, String zh, String en) async {
  final action = find.descendant(
    of: find.byType(Dialog),
    matching: find.text(_localeText(zh, en)),
  );
  expect(action, findsOneWidget);
  await tester.tap(action);
  await tester.pumpAndSettle();
}

Finder _noteField() => find.byKey(const ValueKey('admin_invites_note_field'));

Finder _copyAndCloseButton() => find.descendant(
  of: find.byType(Dialog),
  matching: find.text(_localeText('复制并关闭', 'Copy and close')),
);

VoidCallback _copyAndCloseCallback(WidgetTester tester) {
  final button = _copyAndCloseButton();
  expect(button, findsOneWidget);
  final action = _copyAndCloseActionButton();
  expect(action, findsOneWidget);
  return tester.widget<FilledButton>(action).onPressed!;
}

Finder _copyAndCloseActionButton() => find.ancestor(
  of: _copyAndCloseButton(),
  matching: find.byType(FilledButton),
);

Finder _dialogCancelButton() => find.descendant(
  of: find.byType(Dialog),
  matching: find.text(_localeText('取消', 'Cancel')),
);

void _expectSearchCopy(WidgetTester tester, AppLocale locale) {
  expect(
    tester.widget<TextField>(_searchField(tester)).decoration?.hintText,
    _localeText('搜索邀请码、备注或使用者', 'Search codes, notes or users', locale),
  );
}

void _expectListCopy(
  WidgetTester tester,
  AppLocale locale, {
  required bool populated,
}) {
  final module = _inviteModule();
  expect(module, findsOneWidget);
  expect(
    find.descendant(
      of: module,
      matching: find.text(_localeText('邀请码列表', 'Invite codes', locale)),
    ),
    findsOneWidget,
  );
  expect(_generateButton(), findsOneWidget);
  expect(
    find.descendant(
      of: _generateButton(),
      matching: find.text(
        _localeText('生成邀请码', 'Generate invite codes', locale),
      ),
    ),
    findsOneWidget,
  );
  expect(
    find.descendant(
      of: module,
      matching: find.text(_localeText('邀请码排序', 'Sort invite codes', locale)),
    ),
    findsOneWidget,
  );
  expect(
    find.descendant(
      of: module,
      matching: find.text(_localeText('最新生成优先', 'Newest first', locale)),
    ),
    findsOneWidget,
  );
  _expectSearchCopy(tester, locale);
  expect(
    find.byKey(const ValueKey('admin_invites_pagination_bar')),
    findsOneWidget,
  );
  if (populated) {
    expect(find.text(_unusedCode), findsOneWidget);
    expect(
      find.widgetWithText(
        ChoiceChip,
        _localeText('全部邀请码', 'All invite codes', locale),
      ),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(ChoiceChip, _localeText('未使用', 'Unused', locale)),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(ChoiceChip, _localeText('已使用', 'Used', locale)),
      findsOneWidget,
    );
  } else {
    expect(
      find.text(
        _localeText(
          '暂无邀请码，可生成邀请码供新用户注册',
          'No invite codes yet. Generate codes for new users.',
          locale,
        ),
      ),
      findsOneWidget,
    );
  }
}

void _expectGenerationDialog(WidgetTester tester, AppLocale locale) {
  expect(find.byType(Dialog), findsOneWidget);
  expect(
    find.descendant(
      of: find.byType(Dialog),
      matching: find.text(
        _localeText('生成邀请码', 'Generate invite codes', locale),
      ),
    ),
    findsOneWidget,
  );
  expect(
    find.descendant(
      of: find.byType(Dialog),
      matching: find.text(
        '${_localeText('数量', 'Quantity', locale)}: ${tester.widget<Slider>(find.byKey(const ValueKey('admin_invites_count_slider'))).value.round()}',
      ),
    ),
    findsOneWidget,
  );
  expect(
    tester.widget<TextField>(_noteField()).decoration?.labelText,
    _localeText('备注（可选）', 'Note (optional)', locale),
  );
  expect(
    find.descendant(
      of: find.byType(Dialog),
      matching: find.text(_localeText('生成', 'Generate', locale)),
    ),
    findsOneWidget,
  );
  expect(_dialogCancelButton(), findsOneWidget);
}

void _expectDeleteDialog(WidgetTester tester, AppLocale locale, String code) {
  expect(find.byType(Dialog), findsOneWidget);
  expect(
    find.descendant(
      of: find.byType(Dialog),
      matching: find.text(_localeText('删除邀请码？', 'Delete invite code?', locale)),
    ),
    findsOneWidget,
  );
  expect(
    find.descendant(
      of: find.byType(Dialog),
      matching: find.textContaining(code),
    ),
    findsOneWidget,
  );
  expect(_dialogCancelButton(), findsOneWidget);
  expect(
    find.descendant(
      of: find.byType(Dialog),
      matching: find.text(_localeText('删除', 'Delete', locale)),
    ),
    findsOneWidget,
  );
}

void _expectResultDialog(
  WidgetTester tester,
  AppLocale locale,
  List<String> codes,
) {
  expect(find.byType(Dialog), findsOneWidget);
  expect(
    find.descendant(
      of: find.byType(Dialog),
      matching: find.text(
        _localeText(
          '已生成 ${codes.length} 个邀请码',
          '${codes.length} invite codes generated',
          locale,
        ),
      ),
    ),
    findsOneWidget,
  );
  final generated = tester.widget<SelectableText>(
    find.byKey(const ValueKey('admin_invites_generated_codes')),
  );
  expect(generated.data, codes.join('\n'));
  expect(_copyAndCloseButton(), findsOneWidget);
}

Future<List<String>> _generateAndShowResult(
  WidgetTester tester,
  _InvitesFixture fixture, {
  required int count,
  required String note,
}) async {
  await _openGenerationDialog(tester);
  final sliderFinder = find.byKey(const ValueKey('admin_invites_count_slider'));
  tester.widget<Slider>(sliderFinder).onChanged!(count.toDouble());
  await tester.pumpAndSettle();
  await tester.enterText(_noteField(), note);
  await tester.tap(_dialogPrimaryButton());
  await tester.pumpAndSettle();
  expect(find.byType(Dialog), findsOneWidget);
  expect(fixture.generatedBatches, isNotEmpty);
  return fixture.generatedBatches.last;
}

Future<void> _invalidateAuthority(
  WidgetTester tester,
  _InvitesFixture fixture,
  String boundary,
) async {
  final currentToken = fixture.client.token ?? 'synthetic-invite-token';
  switch (boundary) {
    case 'account replacement':
      fixture.replaceAuth(
        _switchableAuth(
          fixture.client,
          _adminState(userId: 'replacement-invite-admin', token: currentToken),
        ),
      );
      break;
    case 'client replacement':
      fixture.replaceClient(fixture.newClient(token: currentToken));
      break;
    case 'token rotation':
      fixture.client.token = 'rotated-$currentToken';
      break;
    case 'permission revoke and re-grant':
      fixture.replaceAuth(
        _switchableAuth(
          fixture.client,
          _adminState(token: currentToken, permissions: const ['__none__']),
        ),
      );
      await tester.pumpAndSettle();
      fixture.replaceAuth(
        _switchableAuth(fixture.client, _adminState(token: currentToken)),
      );
      break;
    default:
      throw StateError('Unknown invite authority boundary: $boundary');
  }
  await tester.pumpAndSettle();
}

List<String> _installClipboardSpy(WidgetTester tester) {
  final writes = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        final arguments = call.arguments as Map<Object?, Object?>;
        writes.add(arguments['text'] as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return writes;
}

Element _scrollableWithContent(WidgetTester tester, Finder module) {
  for (final element
      in find
          .descendant(of: module, matching: find.byType(Scrollable))
          .evaluate()) {
    final state = tester.state<ScrollableState>(_elementFinder(element));
    if (state.position.maxScrollExtent > 0) return element;
  }
  throw StateError('The Invites content has no scrollable extent.');
}

Finder _elementFinder(Element element) =>
    find.byElementPredicate((candidate) => identical(candidate, element));

Future<void> _captureIfRequested(
  WidgetTester tester,
  _InvitesFixture fixture,
  String name,
) async {
  final directoryPath =
      Platform.environment['DUOYI_ADMIN_INVITES_SCREENSHOT_DIR'];
  if (directoryPath == null || directoryPath.trim().isEmpty) return;
  final screenshotsRoot = Directory('evidence/screenshots').absolute.path;
  final outputDirectory = Directory(directoryPath).absolute.path;
  if (outputDirectory != screenshotsRoot &&
      !outputDirectory.startsWith(
        '$screenshotsRoot${Platform.pathSeparator}',
      )) {
    throw StateError(
      'DUOYI_ADMIN_INVITES_SCREENSHOT_DIR must stay under evidence/screenshots/.',
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

AuthState _adminState({
  String userId = 'invite-admin',
  String token = 'synthetic-invite-token',
  List<String> permissions = const ['invites'],
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

Map<String, dynamic> _inviteFixtureItem(String code) => {
  'code': code,
  'note': 'invite fixture note',
  'used_by': '',
  'used_by_name': '',
  'used_at': null,
  'created_at': '2026-10-12 08:00:00',
};

http.Response _inviteCodesResponse(List<Map<String, dynamic>> items) =>
    _jsonResponse({
      'items': items,
      'total': items.length,
      'limit': 20,
      'offset': 0,
      'has_more': false,
    });

class _InvitesFixture {
  _InvitesFixture({int codeCount = 5}) {
    codes = _initialCodes(codeCount);
    auth = _switchableAuth(
      newClient(token: 'synthetic-invite-token'),
      _adminState(),
    );
    authProviders.add(auth);
  }

  final List<_CapturedRequest> requests = [];
  final List<Map<String, dynamic>> mutationBodies = [];
  final List<AuthProvider> authProviders = [];
  final List<http.Client> transports = [];
  final List<List<String>> generatedBatches = [];
  final ThemeProvider theme = ThemeProvider();
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();
  final GlobalKey screenshotKey = GlobalKey();
  final _RecordingNavigatorObserver routes = _RecordingNavigatorObserver();
  late List<Map<String, dynamic>> codes;
  late AuthProvider auth;
  late StateSetter rebuildHost;
  Completer<http.Response>? _nextMutation;
  Completer<http.Response>? _nextInviteRead;
  http.Response? _nextInviteReadResponse;
  Completer<http.Response>? initialHeldInviteRead;
  int _generatedCodeSerial = 1;

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

  Completer<http.Response> holdNextInviteRead() {
    final completer = Completer<http.Response>();
    _nextInviteRead = completer;
    return completer;
  }

  void failNextInviteRead(http.Response response) {
    _nextInviteReadResponse = response;
  }

  List<_CapturedRequest> get inviteReads => requests
      .where(
        (request) =>
            request.method == 'GET' &&
            request.path == '/api/admin/invite-codes',
      )
      .toList();

  List<_CapturedRequest> get inviteMutations => requests
      .where(
        (request) =>
            request.path.startsWith('/api/admin/invite-codes') &&
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
      if (request.url.path == '/api/admin/invite-codes') {
        final held = _nextInviteRead;
        _nextInviteRead = null;
        if (held != null) return held.future;
        final response = _nextInviteReadResponse;
        _nextInviteReadResponse = null;
        if (response != null) return response;
        return _invitePageResponse(request);
      }
      return _otherGetResponse(request);
    }

    if (request.url.path == '/api/admin/invite-codes' &&
        request.method == 'POST') {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      mutationBodies.add(body);
      final held = _nextMutation;
      _nextMutation = null;
      final response = held == null
          ? _defaultCreateResponse(body)
          : await held.future;
      if (response.statusCode >= 400) return response;
      final responseJson = jsonDecode(response.body) as Map<String, dynamic>;
      final created = (responseJson['codes'] as List<dynamic>? ?? const [])
          .map((code) => code.toString())
          .toList();
      generatedBatches.add(created);
      for (final code in created.reversed) {
        codes.insert(0, {
          'code': code,
          'note': body['note'] ?? '',
          'used_by': '',
          'used_by_name': '',
          'used_at': null,
          'created_at': '2026-10-12 08:00:00',
        });
      }
      return response;
    }

    if (request.method == 'DELETE' &&
        request.url.path.startsWith('/api/admin/invite-codes/')) {
      mutationBodies.add(<String, dynamic>{});
      final held = _nextMutation;
      _nextMutation = null;
      final response = held == null ? _jsonResponse({}) : await held.future;
      if (response.statusCode >= 400) return response;
      final code = Uri.decodeComponent(request.url.path.split('/').last);
      codes.removeWhere((item) => item['code'] == code);
      return response;
    }

    throw StateError('Unexpected Invites fixture request: ${captured.line}');
  }

  http.Response _invitePageResponse(http.Request request) {
    final query = request.url.queryParameters;
    final search = (query['q'] ?? '').toLowerCase();
    final status = query['status'];
    final limit = int.tryParse(query['limit'] ?? '') ?? 20;
    final offset = int.tryParse(query['offset'] ?? '') ?? 0;
    var filtered = codes.where((item) {
      final used = (item['used_by'] ?? '').toString().isNotEmpty;
      if (status == 'unused' && used) return false;
      if (status == 'used' && !used) return false;
      if (search.isNotEmpty) {
        final haystack = [
          item['code'],
          item['note'],
          item['used_by_name'],
        ].map((value) => (value ?? '').toString().toLowerCase()).join(' ');
        if (!haystack.contains(search)) return false;
      }
      return true;
    }).toList();
    switch (query['sort']) {
      case 'code_asc':
        filtered.sort(
          (a, b) => (a['code'] as String).compareTo(b['code'] as String),
        );
        break;
      case 'note_asc':
        filtered.sort(
          (a, b) => (a['note'] as String).compareTo(b['note'] as String),
        );
        break;
      case 'used_desc':
        filtered.sort(
          (a, b) => (b['used_at'] ?? '').toString().compareTo(
            (a['used_at'] ?? '').toString(),
          ),
        );
        break;
    }
    final items = filtered.skip(offset).take(limit).toList();
    return _jsonResponse({
      'items': items,
      'total': filtered.length,
      'limit': limit,
      'offset': offset,
      'has_more': offset + items.length < filtered.length,
    });
  }

  http.Response _otherGetResponse(http.Request request) {
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
          'invites': <String, Object>{'total': codes.length, 'used': 1},
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
      case '/api/admin/users':
      case '/api/admin/backups':
      case '/api/admin/server-backups':
      case '/api/admin/groups':
      case '/api/admin/announcements':
      case '/api/admin/feedback':
      case '/api/admin/audit-log':
        return emptyPage;
      default:
        throw StateError('Unexpected Invites fixture GET: ${request.url}');
    }
  }

  http.Response _defaultCreateResponse(Map<String, dynamic> body) {
    final count = (body['count'] as num?)?.toInt() ?? 1;
    final created = List<String>.generate(
      count,
      (_) =>
          'INV-GENERATED-${(_generatedCodeSerial++).toString().padLeft(4, '0')}',
    );
    return _jsonResponse({'codes': created});
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

List<Map<String, dynamic>> _initialCodes(int count) => [
  {
    'code': _unusedCode,
    'note': _literalNote,
    'used_by': '',
    'used_by_name': '',
    'used_at': null,
    'created_at': '2026-10-01 08:00:00',
  },
  {
    'code': _usedCode,
    'note': 'used invite note',
    'used_by': 'literal-user-1',
    'used_by_name': 'Literal User',
    'used_at': '2026-10-02 08:00:00',
    'created_at': '2026-10-01 08:00:00',
  },
  for (var index = 2; index < count; index++)
    {
      'code': 'INV-LITERAL-${index.toString().padLeft(3, '0')}',
      'note': _literalNote,
      'used_by': '',
      'used_by_name': '',
      'used_at': null,
      'created_at': '2026-10-01 08:00:00',
    },
];

_SwitchableClientAuth _switchableAuth(ApiClient client, AuthState state) =>
    _SwitchableClientAuth(client: client, state: state);

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
}
