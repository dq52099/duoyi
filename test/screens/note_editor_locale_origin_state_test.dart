import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

// ignore: depend_on_referenced_packages
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/design_tokens.dart' show AppSurfaceStyle;
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/i18n_date_format.dart';
import 'package:duoyi/core/note_editor_ui_copy.dart';
import 'package:duoyi/models/note.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/providers/note_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/note_screen.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/app_access_route_gate.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/widget_polish_screenshot_font.dart';

const _captureEnvKey = 'DUOYI_CAPTURE_NOTE_EDITOR_SCREENSHOTS';
const _screenshotDirectory = 'evidence/screenshots/note-editor-20261015';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    I18n.setLocale(AppLocale.zh);
  });

  tearDown(() => I18n.setLocale(AppLocale.zh));

  _registerAttachmentLiveThemeTests();

  testWidgets(
    'Note editor locale changes retain draft, selection and preview',
    (tester) async {
      final fixture = await _mountEditor(tester);
      await _openEditor(tester);

      final editor = find.byType(NoteEditScreen);
      final state = tester.state<State<NoteEditScreen>>(editor);
      await tester.enterText(_editorField(), 'Literal / 混合 draft\nsecond line');
      final editableFinder = find.descendant(
        of: editor,
        matching: find.byType(EditableText),
      );
      final editable = tester.widget<EditableText>(editableFinder);
      final controller = editable.controller;
      final focus = editable.focusNode;
      controller.selection = const TextSelection(
        baseOffset: 2,
        extentOffset: 8,
      );
      await tester.pump();

      for (final locale in [AppLocale.en, AppLocale.zh]) {
        I18n.setLocale(locale);
        await _settleFrames(tester);
        final current = tester.widget<EditableText>(editableFinder);
        expect(tester.state<State<NoteEditScreen>>(editor), same(state));
        expect(current.controller, same(controller));
        expect(current.focusNode, same(focus));
        expect(controller.text, 'Literal / 混合 draft\nsecond line');
        expect(
          controller.selection,
          const TextSelection(baseOffset: 2, extentOffset: 8),
        );
        expect(focus.hasFocus, isTrue);
        expect(
          tester.widget<TextField>(_editorField()).decoration!.hintText,
          I18n.tr('note.editor.hint'),
        );
      }

      await tester.tap(_previewButton());
      await _settleFrames(tester);
      I18n.setLocale(AppLocale.en);
      await _settleFrames(tester);
      expect(tester.state<State<NoteEditScreen>>(editor), same(state));
      expect(find.text('Literal / 混合 draft'), findsOneWidget);
      expect(find.byTooltip(I18n.tr('note.edit')), findsOneWidget);
      expect(controller.text, 'Literal / 混合 draft\nsecond line');
      await _captureScreenshot(tester, fixture, 'locale-preview-en');
      expect(fixture.provider.notes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  for (final locale in AppLocale.values) {
    for (final layout in const [
      (name: 'narrow', size: Size(320, 844), scale: 1.3),
      (name: 'large-text', size: Size(390, 844), scale: 1.6),
      (name: 'accessibility', size: Size(320, 844), scale: 2.0),
      (name: 'landscape', size: Size(568, 320), scale: 1.6),
    ]) {
      testWidgets('Note library metadata fits ${locale.name} ${layout.name}', (
        tester,
      ) async {
        I18n.setLocale(locale);
        final fixture = await _mountEditor(
          tester,
          useLibraryHome: true,
          size: layout.size,
          textScale: layout.scale,
          initialNotes: [
            _note(id: 'metadata-active', content: 'Active note\nBody'),
            _note(
              id: 'metadata-archived',
              content: 'Archived note\nBody',
              archived: true,
            ),
          ],
        );
        final state = tester.state<State<NoteScreen>>(find.byType(NoteScreen));
        final original = fixture.provider.notes.map((n) => n.toJson()).toList();
        await _expectLibraryMetadata(tester, 'active-metadata-active');
        await tester.tap(find.text('${I18n.tr('note.archived')} 1'));
        await _settleFrames(tester);
        await _expectLibraryMetadata(tester, 'archived-metadata-archived');
        for (final next in [
          locale == AppLocale.zh ? AppLocale.en : AppLocale.zh,
          locale,
        ]) {
          I18n.setLocale(next);
          await _settleFrames(tester);
          expect(
            tester.state<State<NoteScreen>>(find.byType(NoteScreen)),
            same(state),
          );
          await _expectLibraryMetadata(tester, 'archived-metadata-archived');
        }
        expect(
          fixture.provider.notes.map((n) => n.toJson()).toList(),
          original,
        );
        await _captureScreenshot(
          tester,
          fixture,
          'library-metadata-${locale.name}-${layout.name}',
        );
      });
    }
  }

  for (final locale in AppLocale.values) {
    testWidgets(
      'Note library date formats retain archived view ${locale.name}',
      (tester) async {
        I18n.setLocale(locale);
        final preferences = PreferencesProvider();
        addTearDown(preferences.dispose);
        await tester.runAsync(preferences.loadFromStorage);
        final fixture = await _mountEditor(
          tester,
          useLibraryHome: true,
          size: const Size(320, 844),
          textScale: 2,
          preferences: preferences,
          initialNotes: [
            _note(id: 'format-active', content: 'Active format note'),
            _note(
              id: 'format-archived',
              content: 'Archived format note',
              archived: true,
            ),
          ],
        );
        await tester.tap(find.text('${I18n.tr('note.archived')} 1'));
        await _settleFrames(tester);
        final state = tester.state<State<NoteScreen>>(find.byType(NoteScreen));
        final original = fixture.provider.notes.map((n) => n.toJson()).toList();
        for (final pattern in I18nDateFormat.supportedPatterns) {
          await tester.runAsync(() => preferences.setDateFormat(pattern));
          await _settleFrames(tester);
          expect(preferences.dateFormat, pattern);
          expect(
            tester.state<State<NoteScreen>>(find.byType(NoteScreen)),
            same(state),
          );
          expect(
            find.byKey(const ValueKey('active-format-active')),
            findsNothing,
          );
          await _expectLibraryMetadata(
            tester,
            'archived-format-archived',
            pattern: pattern,
          );
        }
        expect(
          fixture.provider.notes.map((n) => n.toJson()).toList(),
          original,
        );
        await _captureScreenshot(
          tester,
          fixture,
          'library-date-format-${locale.name}-accessibility',
        );
      },
    );
  }

  testWidgets('Note library locale retains search and archived selection', (
    tester,
  ) async {
    final fixture = await _mountEditor(
      tester,
      useLibraryHome: true,
      initialNotes: [
        _note(id: 'active-locale', content: 'needle active note'),
        _note(
          id: 'archived-locale',
          content: 'needle archived note',
          archived: true,
        ),
      ],
    );
    final library = find.byType(NoteScreen);
    final state = tester.state<State<NoteScreen>>(library);
    final search = find.byType(TextField).first;
    await tester.enterText(search, 'needle');
    await tester.tap(find.text('归档 1'));
    await _settleFrames(tester);
    await tester.tap(search);
    final searchController = tester.widget<TextField>(search).controller!;
    final searchFocus = tester
        .widget<EditableText>(
          find.descendant(of: search, matching: find.byType(EditableText)),
        )
        .focusNode;
    searchController.selection = const TextSelection(
      baseOffset: 1,
      extentOffset: 4,
    );
    await tester.pump();
    expect(find.text('needle archived note'), findsOneWidget);
    expect(find.text('needle active note'), findsNothing);

    for (final locale in [AppLocale.en, AppLocale.zh]) {
      I18n.setLocale(locale);
      await _settleFrames(tester);
      expect(tester.state<State<NoteScreen>>(library), same(state));
      expect(
        tester.widget<TextField>(search).controller,
        same(searchController),
      );
      expect(searchController.text, 'needle');
      expect(
        searchController.selection,
        const TextSelection(baseOffset: 1, extentOffset: 4),
      );
      expect(
        tester
            .widget<EditableText>(
              find.descendant(of: search, matching: find.byType(EditableText)),
            )
            .focusNode,
        same(searchFocus),
      );
      expect(searchFocus.hasFocus, isTrue);
      expect(find.text('needle archived note'), findsOneWidget);
      expect(find.text('needle active note'), findsNothing);
    }
    expect(fixture.provider.notes, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Reset invalidates retained library FAB and card open callbacks',
    (tester) async {
      final fixture = await _mountEditor(
        tester,
        useLibraryHome: true,
        initialNotes: [
          _note(id: 'old-entry', content: 'retained card title\ncard body'),
        ],
      );
      final staleFab = tester
          .widget<FloatingActionButton>(find.byType(FloatingActionButton))
          .onPressed!;
      final staleCardOpen = tester
          .widget<InkWell>(_noteCardOpen('old-entry', 'retained card title'))
          .onTap!;
      final oldRoute = fixture.routeGate.currentRoute;

      fixture.provider.resetLocalState();
      await _settleFrames(tester);
      staleFab();
      staleCardOpen();
      await _settleFrames(tester);

      expect(fixture.routeGate.currentRoute, same(oldRoute));
      expect(find.byType(NoteEditScreen), findsNothing);
      expect(find.byType(NoteScreen), findsOneWidget);
      expect(find.text('retained card title'), findsNothing);

      await tester.tap(find.byType(FloatingActionButton));
      await _settleFrames(tester);
      expect(find.byType(NoteEditScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Locked library swipe keeps note; unlocked swipe archives it', (
    tester,
  ) async {
    final fixture = await _mountEditor(
      tester,
      useLibraryHome: true,
      initialNotes: [_note(id: 'swipe-note', content: 'swipe me into archive')],
    );
    final initialWrites = fixture.store.noteWriteAttempts;
    fixture.lock.setLocked(true);
    await tester.drag(_noteCard('swipe-note'), const Offset(-600, 0));
    await _settleFrames(tester);
    expect(fixture.provider.activeNotes, hasLength(1));
    expect(fixture.provider.archivedNotes, isEmpty);
    expect(fixture.store.noteWriteAttempts, initialWrites);
    expect(tester.takeException(), isNull);

    fixture.lock.setLocked(false);
    await _settleFrames(tester);
    await tester.drag(_noteCard('swipe-note'), const Offset(-600, 0));
    await _settleFrames(tester);
    await _drainWrites(tester);
    expect(fixture.provider.activeNotes, isEmpty);
    expect(fixture.provider.archivedNotes, hasLength(1));
    expect(fixture.provider.archivedNotes.single.id, 'swipe-note');
    expect(fixture.store.noteWriteAttempts, initialWrites + 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Library menu actions acknowledge pin and preserve explicit target',
    (tester) async {
      final fixture = await _mountEditor(
        tester,
        useLibraryHome: true,
        initialNotes: [_note(id: 'menu-note', content: 'menu note')],
      );
      await tester.tap(find.byTooltip('更多操作'));
      await _settleFrames(tester);
      await tester.tap(find.text('置顶'));
      await _drainWrites(tester);
      expect(fixture.provider.notes.single.pinned, isTrue);
      expect(fixture.provider.notes.single.archived, isFalse);

      await tester.tap(find.byTooltip('更多操作'));
      await _settleFrames(tester);
      await tester.tap(find.text('取消置顶'));
      await _drainWrites(tester);
      expect(fixture.provider.notes.single.pinned, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Library action failure keeps card and exposes localized retry', (
    tester,
  ) async {
    final fixture = await _mountEditor(
      tester,
      useLibraryHome: true,
      initialNotes: [_note(id: 'retry-note', content: 'retry note')],
    );
    fixture.store.failNextNoteWrite = true;
    await tester.tap(find.byTooltip('更多操作'));
    await _settleFrames(tester);
    await tester.tap(find.text('置顶'));
    await _drainWrites(tester);
    expect(fixture.provider.notes.single.pinned, isFalse);
    expect(find.text('操作失败，内容未变更，请重试'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await _drainWrites(tester);
    expect(fixture.provider.notes.single.pinned, isTrue);
    expect(find.text('操作失败，内容未变更，请重试'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final action in ['pin', 'unpin', 'archive', 'restore', 'delete']) {
    for (final result in ['held', 'false', 'throw']) {
      testWidgets('Library transaction $action $result commits or retries', (
        tester,
      ) async {
        final restoring = action == 'restore';
        final original = _note(
          id: 'transaction-note',
          content: 'Transaction note\nKeep this body',
          archived: restoring,
        ).copyWith(pinned: action == 'unpin' || action == 'archive');
        final fixture = await _mountEditor(
          tester,
          useLibraryHome: true,
          initialNotes: [original],
        );
        if (restoring) {
          await tester.tap(find.text('归档 1'));
          await _settleFrames(tester);
        }
        final state = tester.state(find.byType(NoteScreen));
        final card = _libraryCard('transaction-note', archived: restoring);
        final oldOpen = tester
            .widget<InkWell>(
              find
                  .ancestor(
                    of: find.descendant(
                      of: card,
                      matching: find.text('Transaction note'),
                    ),
                    matching: find.byType(InkWell),
                  )
                  .first,
            )
            .onTap!;
        final repeatAction = _retainedLibraryAction(tester, card, action);
        final writes = fixture.store.noteWriteAttempts;
        var persisted = 0;
        fixture.provider.onLocalMutationPersisted = () => persisted++;
        if (result == 'held') {
          fixture.store.armHold();
        } else {
          fixture.store.failNextNoteWrite = true;
          fixture.store.throwOnNoteFailure = result == 'throw';
        }

        await _selectLibraryAction(tester, action);
        if (result == 'held') {
          await _waitForHeldWrite(tester, fixture.store);
          expect(fixture.provider.notes.single.toJson(), original.toJson());
          expect(persisted, 0);
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
          expect(find.byTooltip(I18n.tr('note.more')), findsNothing);
          await _invoke(tester, repeatAction);
          await _invoke(tester, oldOpen);
          expect(find.byType(NoteEditScreen), findsNothing);
          expect(fixture.store.noteWriteAttempts, writes + 1);
          I18n.setLocale(AppLocale.en);
          await _settleFrames(tester);
          expect(fixture.provider.notes.single.toJson(), original.toJson());
          if (action == 'pin') {
            await _captureScreenshot(tester, fixture, 'library-action-busy-en');
          }
          await _releaseHeldWrite(tester, fixture);
        } else {
          await _drainWrites(tester);
          expect(fixture.provider.notes.single.toJson(), original.toJson());
          expect(persisted, 0);
          expect(card, findsOneWidget);
          expect(find.text(I18n.tr('note.action.failed')), findsOneWidget);
          I18n.setLocale(AppLocale.en);
          await _settleFrames(tester);
          expect(
            find.text('Action failed. Nothing changed. Try again.'),
            findsOneWidget,
          );
          await tester.tap(find.text('Retry'));
          await _drainWrites(tester);
        }

        expect(tester.state(find.byType(NoteScreen)), same(state));
        expect(persisted, 1);
        expect(find.text(I18n.tr('note.action.failed')), findsNothing);
        if (action == 'delete') {
          expect(fixture.provider.notes, isEmpty);
          final prefs = await SharedPreferences.getInstance();
          final deleted =
              jsonDecode(prefs.getString('sync_deleted_items')!) as Map;
          expect(
            (deleted['notes'] as Map).containsKey('transaction-note'),
            isTrue,
          );
        } else {
          final note = fixture.provider.notes.single;
          expect(note.pinned, action == 'pin');
          expect(note.archived, action == 'archive');
          expect(note.content, original.content);
          final snapshot = note.toJson();
          await tester.runAsync(fixture.provider.loadFromStorage);
          await _settleFrames(tester);
          expect(fixture.provider.notes.single.toJson(), snapshot);
        }
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final boundary in ['cover', 'lock', 'reset', 'dispose']) {
    testWidgets('Library transaction held pin cancels on $boundary', (
      tester,
    ) async {
      final original = _note(id: 'guarded-note', content: 'Guarded note');
      final fixture = await _mountEditor(
        tester,
        useLibraryHome: true,
        initialNotes: [original],
      );
      fixture.store.armHold();
      await _selectLibraryAction(tester, 'pin');
      await _waitForHeldWrite(tester, fixture.store);
      if (boundary == 'cover') {
        _coverAndReturnInSameFrame(tester, fixture);
      } else if (boundary == 'lock') {
        fixture.lock.setLocked(true);
        fixture.lock.setLocked(false);
      } else if (boundary == 'reset') {
        AccountLocalDataCleaner.invalidateInFlightAccountWrites();
        fixture.provider.resetLocalState();
      } else {
        await tester.pumpWidget(const SizedBox.shrink());
      }
      await _pumpFrames(tester, count: 35);
      await _releaseHeldWrite(tester, fixture);
      expect(find.text(I18n.tr('note.action.failed')), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      if (boundary == 'reset') {
        expect(fixture.provider.notes, isEmpty);
      } else {
        expect(fixture.provider.notes.single.toJson(), original.toJson());
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final restoring in [false, true]) {
    testWidgets(
      'Library transaction swipe restore=$restoring waits and retries',
      (tester) async {
        final original = _note(
          id: 'swipe-retry',
          content: 'Swipe retry',
          archived: restoring,
        );
        final fixture = await _mountEditor(
          tester,
          useLibraryHome: true,
          initialNotes: [original],
        );
        if (restoring) {
          await tester.tap(find.text('归档 1'));
          await _settleFrames(tester);
        }
        final card = _libraryCard('swipe-retry', archived: restoring);
        fixture.store.armHold();
        fixture.store.failNextNoteWrite = true;
        await tester.drag(card, const Offset(-600, 0));
        await _settleFrames(tester);
        await _waitForHeldWrite(tester, fixture.store);
        expect(fixture.provider.notes.single.toJson(), original.toJson());
        await _releaseHeldWrite(tester, fixture);
        expect(card, findsOneWidget);
        expect(find.text(I18n.tr('note.action.failed')), findsOneWidget);
        await tester.tap(find.text('重试'));
        await _drainWrites(tester);
        expect(fixture.provider.notes.single.archived, !restoring);
        expect(card, findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Library transaction delete tombstone rejection restores and retries',
    (tester) async {
      final original = _note(id: 'delete-rollback', content: 'Delete rollback');
      final fixture = await _mountEditor(
        tester,
        useLibraryHome: true,
        initialNotes: [original],
      );
      final prefs = await SharedPreferences.getInstance();
      await tester.runAsync(
        () => prefs.setString(
          'sync_deleted_items',
          jsonEncode({
            'todos': {'keep-todo': '2026-10-15T12:00:00Z'},
          }),
        ),
      );
      fixture.store.failNextTombstoneWrite = true;
      await _selectLibraryAction(tester, 'delete');
      await _drainWrites(tester);
      expect(fixture.provider.notes.single.toJson(), original.toJson());
      expect(find.text(I18n.tr('note.action.failed')), findsOneWidget);
      final stored =
          jsonDecode(prefs.getStringList('duoyi_notes')!.single) as Map;
      expect(stored['id'], original.id);
      var tombstones =
          jsonDecode(prefs.getString('sync_deleted_items')!) as Map;
      expect((tombstones['todos'] as Map).containsKey('keep-todo'), isTrue);
      expect(tombstones['notes'], isNull);
      await tester.tap(find.text('重试'));
      await _drainWrites(tester);
      expect(fixture.provider.notes, isEmpty);
      tombstones = jsonDecode(prefs.getString('sync_deleted_items')!) as Map;
      expect((tombstones['notes'] as Map).containsKey(original.id), isTrue);
      expect((tombstones['todos'] as Map).containsKey('keep-todo'), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Library transaction reset hides failure and rejects retained retry',
    (tester) async {
      final fixture = await _mountEditor(
        tester,
        useLibraryHome: true,
        initialNotes: [_note(id: 'same-id', content: 'Prior note')],
      );
      fixture.store.failNextNoteWrite = true;
      await _selectLibraryAction(tester, 'pin');
      await _drainWrites(tester);
      final staleRetry = tester
          .widget<TextButton>(find.widgetWithText(TextButton, '重试'))
          .onPressed!;
      fixture.provider.resetLocalState();
      await tester.runAsync(
        () => fixture.provider.addOrUpdateNotePersisted(
          _note(id: 'same-id', content: 'Replacement note'),
        ),
      );
      await _settleFrames(tester);
      final writes = fixture.store.noteWriteAttempts;
      expect(find.text(I18n.tr('note.action.failed')), findsNothing);
      await _invoke(tester, staleRetry);
      await _drainWrites(tester);
      expect(fixture.store.noteWriteAttempts, writes);
      expect(fixture.provider.notes.single.pinned, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  for (final locale in AppLocale.values) {
    for (final layout in [
      (name: 'large-text', size: const Size(320, 844), scale: 2.0),
      (name: 'landscape', size: const Size(568, 320), scale: 1.6),
    ]) {
      testWidgets('Library transaction layout $locale $layout', (tester) async {
        I18n.setLocale(locale);
        final fixture = await _mountEditor(
          tester,
          useLibraryHome: true,
          size: layout.size,
          textScale: layout.scale,
          initialNotes: [
            _note(
              id: 'layout-action',
              content: 'Action note\nPreserve this body',
            ),
          ],
        );
        final state = tester.state(find.byType(NoteScreen));
        fixture.store.failNextNoteWrite = true;
        await _selectLibraryAction(tester, 'pin');
        await _drainWrites(tester);
        final error = find.text(I18n.tr('note.action.failed'));
        expect(error, findsOneWidget);
        await tester.ensureVisible(error);
        await _settleFrames(tester);
        final card = _libraryCard('layout-action');
        expect(
          tester.getRect(error).left,
          greaterThanOrEqualTo(tester.getRect(card).left),
        );
        expect(
          tester.getRect(error).right,
          lessThanOrEqualTo(tester.getRect(card).right),
        );
        final retry = find.widgetWithText(TextButton, I18n.tr('action.retry'));
        // Error copy uses the card's full content width; Retry has its own row.
        expect(
          tester.getRect(error).width,
          greaterThanOrEqualTo(tester.getRect(card).width - 40),
        );
        expect(
          tester.getRect(retry).top,
          greaterThanOrEqualTo(tester.getRect(error).bottom),
        );
        final suffix = '${locale.name}-${layout.name}';
        await _captureScreenshot(
          tester,
          fixture,
          'library-action-failed-$suffix',
        );
        await tester.ensureVisible(retry);
        await _settleFrames(tester);
        expect(retry.hitTestable(), findsOneWidget);
        fixture.store.armHold();
        await tester.tap(retry);
        await _settleFrames(tester);
        await _waitForHeldWrite(tester, fixture.store);
        expect(fixture.provider.notes.single.pinned, isFalse);
        final progress = find.byType(CircularProgressIndicator);
        expect(progress, findsOneWidget);
        await tester.ensureVisible(progress);
        await _settleFrames(tester);
        expect(
          tester.widget<CircularProgressIndicator>(progress).semanticsLabel,
          NoteEditorUiCopy.saving,
        );
        await _captureScreenshot(
          tester,
          fixture,
          'library-action-busy-$suffix',
        );
        await _releaseHeldWrite(tester, fixture);
        expect(fixture.provider.notes.single.pinned, isTrue);
        expect(tester.state(find.byType(NoteScreen)), same(state));
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('Held save is busy and repeated callback writes only once', (
    tester,
  ) async {
    final fixture = await _mountEditor(tester);
    await _openEditor(tester);
    await tester.enterText(_editorField(), 'single acknowledged note');
    final stalePreview = tester.widget<IconButton>(_previewButton()).onPressed!;
    fixture.store.armHold();

    final save = tester.widget<IconButton>(_saveButton()).onPressed!;
    await _invoke(tester, save);
    await _waitForHeldWrite(tester, fixture.store);
    expect(fixture.store.noteWriteAttempts, 1);
    expect(tester.widget<IconButton>(_saveButton()).onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await _captureScreenshot(tester, fixture, 'save-busy');
    await _invoke(tester, stalePreview);
    expect(find.byType(EditableText), findsOneWidget);
    expect(find.byTooltip(I18n.tr('note.preview')), findsOneWidget);

    await _invoke(tester, save);
    expect(fixture.store.noteWriteAttempts, 1);
    expect(fixture.provider.notes, isEmpty);

    await _releaseHeldWrite(tester, fixture);
    expect(fixture.provider.notes, hasLength(1));
    expect(fixture.provider.notes.single.content, 'single acknowledged note');
    expect(fixture.store.noteWriteAttempts, 1);
    expect(find.byType(NoteEditScreen), findsNothing);
    expect(find.text('Editor parent'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Rejected save keeps the draft and allows a successful retry', (
    tester,
  ) async {
    final fixture = await _mountEditor(tester);
    await _openEditor(tester);
    await tester.enterText(_editorField(), 'retry the same draft');
    fixture.store.failNextNoteWrite = true;

    await _saveAndDrain(tester);
    expect(fixture.store.noteWriteAttempts, 1);
    expect(fixture.provider.notes, isEmpty);
    expect(find.byType(NoteEditScreen), findsOneWidget);
    expect(
      tester.widget<TextField>(_editorField()).controller!.text,
      'retry the same draft',
    );
    expect(find.text('保存失败，草稿已保留，请重试'), findsOneWidget);
    await _captureScreenshot(tester, fixture, 'save-failed');

    I18n.setLocale(AppLocale.en);
    await _settleFrames(tester);
    expect(
      find.text('Could not save note. Your draft is still here. Try again.'),
      findsOneWidget,
    );
    await _saveAndDrain(tester);
    expect(fixture.store.noteWriteAttempts, 2);
    expect(fixture.provider.notes, hasLength(1));
    expect(fixture.provider.notes.single.content, 'retry the same draft');
    expect(find.byType(NoteEditScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Same-frame cover and return cancels a held save', (
    tester,
  ) async {
    final fixture = await _mountEditor(tester);
    await _openEditor(tester);
    await tester.enterText(_editorField(), 'covered note draft');
    fixture.store.armHold();
    final save = tester.widget<IconButton>(_saveButton()).onPressed!;
    await _invoke(tester, save);
    await _waitForHeldWrite(tester, fixture.store);

    final editorRoute = fixture.routeGate.currentRoute;
    _coverAndReturnInSameFrame(tester, fixture);
    await _pumpFrames(tester, count: 35);
    expect(fixture.routeGate.currentRoute, same(editorRoute));
    await _releaseHeldWrite(tester, fixture);

    expect(fixture.provider.notes, isEmpty);
    expect(find.byType(NoteEditScreen), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('保存失败，草稿已保留，请重试'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Lock and unlock cancels held save but a fresh save succeeds', (
    tester,
  ) async {
    final fixture = await _mountEditor(tester);
    await _openEditor(tester);
    await tester.enterText(_editorField(), 'lock interrupted draft');
    fixture.store.armHold();
    await _invoke(tester, tester.widget<IconButton>(_saveButton()).onPressed!);
    await _waitForHeldWrite(tester, fixture.store);

    fixture.lock.setLocked(true);
    fixture.lock.setLocked(false);
    await _settleFrames(tester);
    await _releaseHeldWrite(tester, fixture);
    expect(fixture.provider.notes, isEmpty);
    expect(find.byType(NoteEditScreen), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    await _saveAndDrain(tester);
    expect(fixture.provider.notes, hasLength(1));
    expect(fixture.provider.notes.single.content, 'lock interrupted draft');
    expect(find.byType(NoteEditScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Account reset cancels a held save and leaves no success state', (
    tester,
  ) async {
    final fixture = await _mountEditor(tester);
    await _openEditor(tester);
    await tester.enterText(_editorField(), 'prior account draft');
    fixture.store.armHold();
    await _invoke(tester, tester.widget<IconButton>(_saveButton()).onPressed!);
    await _waitForHeldWrite(tester, fixture.store);

    AccountLocalDataCleaner.invalidateInFlightAccountWrites();
    fixture.provider.resetLocalState();
    await _settleFrames(tester);
    await _releaseHeldWrite(tester, fixture);

    expect(fixture.provider.notes, isEmpty);
    expect(find.byType(NoteEditScreen), findsOneWidget);
    expect(find.text('页面状态已变更，请返回后重新打开便签'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    await _captureScreenshot(tester, fixture, 'expired-after-account-reset');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Late held save completion after editor disposal is ignored', (
    tester,
  ) async {
    final fixture = await _mountEditor(tester);
    await _openEditor(tester);
    await tester.enterText(_editorField(), 'dismissed note draft');
    fixture.store.armHold();
    await _invoke(tester, tester.widget<IconButton>(_saveButton()).onPressed!);
    await _waitForHeldWrite(tester, fixture.store);

    fixture.navigator.currentState!.pop();
    await _pumpFrames(tester, count: 40);
    expect(find.byType(NoteEditScreen), findsNothing);
    await _releaseHeldWrite(tester, fixture);

    expect(fixture.provider.notes, isEmpty);
    expect(find.text('Editor parent'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Covered and locked formatting callbacks expire permanently', (
    tester,
  ) async {
    final fixture = await _mountEditor(tester);
    await _openEditor(tester);
    await tester.enterText(_editorField(), 'draft');
    final controller = tester.widget<TextField>(_editorField()).controller!;
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    await tester.pump();

    final coveredCallback = tester
        .widget<IconButton>(_formatButton(Icons.format_bold))
        .onPressed!;
    _coverAndReturnInSameFrame(tester, fixture);
    await _settleFrames(tester);
    await _invoke(tester, coveredCallback);
    expect(controller.text, 'draft');

    final lockedCallback = tester
        .widget<IconButton>(_formatButton(Icons.format_bold))
        .onPressed!;
    fixture.lock.setLocked(true);
    fixture.lock.setLocked(false);
    await _settleFrames(tester);
    await _invoke(tester, lockedCallback);
    expect(controller.text, 'draft');

    await _invoke(
      tester,
      tester.widget<IconButton>(_formatButton(Icons.format_bold)).onPressed!,
    );
    expect(controller.text, '**draft**');
    expect(fixture.provider.notes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Covered attachment callback is stale while a fresh one opens', (
    tester,
  ) async {
    final fixture = await _mountEditor(tester);
    await _openEditor(tester);
    final oldCallback = tester
        .widget<IconButton>(_attachmentButton())
        .onPressed!;
    _coverAndReturnInSameFrame(tester, fixture);
    await _settleFrames(tester);
    await _invoke(tester, oldCallback);
    expect(find.text('添加附件'), findsNothing);

    await tester.tap(_attachmentButton());
    await _settleFrames(tester);
    expect(find.text('添加附件'), findsOneWidget);
    fixture.navigator.currentState!.pop();
    await _settleFrames(tester);
    expect(find.byType(NoteEditScreen), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Attachment chooser and form update locale without losing fields',
    (tester) async {
      final fixture = await _mountEditor(tester);
      await _openEditor(tester);
      await tester.enterText(_editorField(), 'editor draft');
      final editorController = tester
          .widget<TextField>(_editorField())
          .controller!;
      editorController.selection = const TextSelection(
        baseOffset: 1,
        extentOffset: 5,
      );
      final editorState = tester.state<State<NoteEditScreen>>(
        find.byType(NoteEditScreen),
      );

      await tester.tap(_attachmentButton());
      await _settleFrames(tester);
      expect(find.text('添加附件'), findsOneWidget);
      expect(
        tester.widget<BottomSheet>(find.byType(BottomSheet)).showDragHandle,
        isFalse,
      );
      await _captureScreenshot(tester, fixture, 'attachment-chooser-zh');
      I18n.setLocale(AppLocale.en);
      await _settleFrames(tester);
      expect(find.text('Add attachment'), findsOneWidget);
      await _captureScreenshot(tester, fixture, 'attachment-chooser-en');
      expect(
        tester.state<State<NoteEditScreen>>(find.byType(NoteEditScreen)),
        same(editorState),
      );
      expect(editorController.text, 'editor draft');
      expect(
        editorController.selection,
        const TextSelection(baseOffset: 1, extentOffset: 5),
      );

      await tester.tap(find.text('Add link or local path'));
      await _settleFrames(tester);
      await tester.enterText(_attachmentField('note-attachment-name'), 'guide');
      await tester.enterText(
        _attachmentField('note-attachment-location'),
        'https://example.test/guide.pdf',
      );
      final location = tester.widget<TextField>(
        _attachmentField('note-attachment-location'),
      );
      final locationController = location.controller!;
      final locationFocus = tester
          .widget<EditableText>(
            find.descendant(
              of: _attachmentField('note-attachment-location'),
              matching: find.byType(EditableText),
            ),
          )
          .focusNode;
      locationController.selection = const TextSelection(
        baseOffset: 3,
        extentOffset: 8,
      );
      await tester.pump();

      I18n.setLocale(AppLocale.zh);
      await _settleFrames(tester);
      expect(
        tester
            .widget<TextField>(_attachmentField('note-attachment-name'))
            .decoration!
            .labelText,
        '名称',
      );
      expect(
        tester
            .widget<TextField>(_attachmentField('note-attachment-location'))
            .decoration!
            .labelText,
        '链接或本地路径',
      );
      final updatedLocation = tester.widget<EditableText>(
        find.descendant(
          of: _attachmentField('note-attachment-location'),
          matching: find.byType(EditableText),
        ),
      );
      expect(updatedLocation.controller, same(locationController));
      expect(updatedLocation.focusNode, same(locationFocus));
      expect(locationFocus.hasFocus, isTrue);
      expect(
        locationController.selection,
        const TextSelection(baseOffset: 3, extentOffset: 8),
      );
      expect(editorController.text, 'editor draft');

      await _captureScreenshot(tester, fixture, 'attachment-form-zh');
      I18n.setLocale(AppLocale.en);
      await _settleFrames(tester);
      await _captureScreenshot(tester, fixture, 'attachment-form-en');
      await tester.tap(find.text('Cancel'));
      await _settleFrames(tester);
      expect(find.byType(NoteEditScreen), findsOneWidget);
      expect(fixture.provider.notes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Empty attachment location stays open and translates its error', (
    tester,
  ) async {
    final fixture = await _mountEditor(tester);
    await _openEditor(tester);
    await _openManualAttachmentForm(tester);

    await tester.tap(_attachmentSubmit());
    await _settleFrames(tester);
    expect(find.text('请填写链接或本地路径'), findsOneWidget);
    expect(_attachmentField('note-attachment-location'), findsOneWidget);
    expect(find.byType(NoteEditScreen), findsOneWidget);
    await _captureScreenshot(tester, fixture, 'attachment-required-zh');

    I18n.setLocale(AppLocale.en);
    await _settleFrames(tester);
    expect(find.text('Enter a link or local path'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(_attachmentField('note-attachment-location'))
          .decoration!
          .labelText,
      'Link or local path',
    );
    await _captureScreenshot(tester, fixture, 'attachment-required-en');
    await tester.enterText(
      _attachmentField('note-attachment-location'),
      '/tmp/guide.pdf',
    );
    await _settleFrames(tester);
    expect(find.text('Enter a link or local path'), findsNothing);
    await tester.tap(find.text('Cancel'));
    await _settleFrames(tester);
    expect(fixture.provider.notes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Manual attachment alone can be saved as a note', (tester) async {
    final fixture = await _mountEditor(tester);
    await _openEditor(tester);
    await _openManualAttachmentForm(tester);
    await tester.enterText(
      _attachmentField('note-attachment-name'),
      'manual.pdf',
    );
    await tester.enterText(
      _attachmentField('note-attachment-location'),
      'https://example.test/manual.pdf',
    );
    await tester.enterText(
      _attachmentField('note-attachment-type'),
      'application/pdf',
    );
    await tester.tap(_attachmentSubmit());
    await _settleFrames(tester);

    expect(find.text('manual.pdf'), findsOneWidget);
    await _captureScreenshot(tester, fixture, 'attachment-only-note');
    await _saveAndDrain(tester);
    expect(fixture.provider.notes, hasLength(1));
    final saved = fixture.provider.notes.single;
    expect(saved.content, isEmpty);
    expect(saved.attachments, hasLength(1));
    expect(saved.attachments.single.name, 'manual.pdf');
    expect(saved.attachments.single.uri, 'https://example.test/manual.pdf');
    expect(saved.attachments.single.mimeType, 'application/pdf');
    expect(find.text('Editor parent'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Empty existing note deletion can be retried after storage failure',
    (tester) async {
      final original = _note(id: 'empty-existing', content: '');
      final fixture = await _mountEditor(
        tester,
        editorNote: original,
        initialNotes: [original],
      );
      await _openEditor(tester);
      expect(
        tester.widget<TextField>(_editorField()).controller!.text,
        isEmpty,
      );
      final writesBeforeDelete = fixture.store.noteWriteAttempts;
      fixture.store.failNextNoteWrite = true;

      await _saveAndDrain(tester);
      expect(fixture.provider.notes, hasLength(1));
      expect(fixture.provider.notes.single.id, original.id);
      expect(find.byType(NoteEditScreen), findsOneWidget);
      expect(find.text('保存失败，草稿已保留，请重试'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await _saveAndDrain(tester);
      expect(fixture.provider.notes, isEmpty);
      expect(fixture.store.noteWriteAttempts, greaterThan(writesBeforeDelete));
      expect(find.byType(NoteEditScreen), findsNothing);
      expect(find.text('Editor parent'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Portable file picker cancellation returns to the editor', (
    tester,
  ) async {
    final fixture = await _mountEditor(tester);
    final selector = _DeferredFileSelector();
    fixture.installFileSelector(selector);
    await _openEditor(tester);
    await _openAttachmentSheet(tester);
    await tester.tap(find.text('从系统文件选择'));
    await _settleFrames(tester);
    expect(selector.opened.isCompleted, isTrue);

    selector.release.complete(null);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await _settleFrames(tester);
    expect(selector.openCount, 1);
    expect(find.byType(NoteEditScreen), findsOneWidget);
    expect(_attachmentField('note-attachment-location'), findsNothing);
    expect(tester.widget<IconButton>(_attachmentButton()).onPressed, isNotNull);
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Late file result after editor disposal is ignored', (
    tester,
  ) async {
    final fixture = await _mountEditor(tester);
    final selector = _DeferredFileSelector();
    fixture.installFileSelector(selector);
    await _openEditor(tester);
    await _openAttachmentSheet(tester);
    await tester.tap(find.text('从系统文件选择'));
    await _settleFrames(tester);
    expect(selector.opened.isCompleted, isTrue);

    fixture.navigator.currentState!.pop();
    await _pumpFrames(tester, count: 40);
    expect(find.byType(NoteEditScreen), findsNothing);
    selector.release.complete(XFile('/tmp/late.pdf'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await _settleFrames(tester);

    expect(find.text('Editor parent'), findsOneWidget);
    expect(fixture.provider.notes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Late file result after account reset is ignored', (
    tester,
  ) async {
    final fixture = await _mountEditor(tester);
    final selector = _DeferredFileSelector();
    fixture.installFileSelector(selector);
    await _openEditor(tester);
    await _openAttachmentSheet(tester);
    await tester.tap(find.text('从系统文件选择'));
    await _settleFrames(tester);
    expect(selector.opened.isCompleted, isTrue);

    AccountLocalDataCleaner.invalidateInFlightAccountWrites();
    fixture.provider.resetLocalState();
    await _settleFrames(tester);
    selector.release.complete(XFile('/tmp/prior-account.pdf'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await _settleFrames(tester);

    expect(find.byType(NoteEditScreen), findsOneWidget);
    expect(find.text('页面状态已变更，请返回后重新打开便签'), findsOneWidget);
    expect(find.text('prior-account.pdf'), findsNothing);
    expect(fixture.provider.notes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Manual form submit cannot pop a newer covering route', (
    tester,
  ) async {
    final fixture = await _mountEditor(tester);
    await _openEditor(tester);
    await _openManualAttachmentForm(tester);
    await tester.enterText(
      _attachmentField('note-attachment-location'),
      '/tmp/old-form.pdf',
    );
    final staleSubmit = tester
        .widget<FilledButton>(_attachmentSubmit())
        .onPressed!;
    unawaited(
      fixture.navigator.currentState!.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Newer covering route')),
        ),
      ),
    );
    await _settleFrames(tester);
    expect(find.text('Newer covering route'), findsOneWidget);

    await _invoke(tester, staleSubmit);
    await _settleFrames(tester);
    expect(find.text('Newer covering route'), findsOneWidget);
    expect(find.byType(NoteEditScreen, skipOffstage: false), findsOneWidget);
    expect(fixture.provider.notes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Account reset removes only the editor-owned attachment form', (
    tester,
  ) async {
    final fixture = await _mountEditor(tester);
    await _openEditor(tester);
    final editorRoute = fixture.routeGate.currentRoute;
    await _openManualAttachmentForm(tester);

    AccountLocalDataCleaner.invalidateInFlightAccountWrites();
    fixture.provider.resetLocalState();
    await _settleFrames(tester);

    expect(_attachmentField('note-attachment-location'), findsNothing);
    expect(find.byType(NoteEditScreen), findsOneWidget);
    expect(fixture.routeGate.currentRoute, same(editorRoute));
    expect(find.text('页面状态已变更，请返回后重新打开便签'), findsOneWidget);
    expect(find.text('Editor parent'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Commit survives same-frame lock and retry reuses its note ID', (
    tester,
  ) async {
    final fixture = await _mountEditor(tester);
    await _openEditor(tester);
    await tester.enterText(_editorField(), 'confirmed before lock');
    fixture.provider.onLocalMutationPersisted = () {
      fixture.lock.setLocked(true);
      fixture.lock.setLocked(false);
    };

    await _saveAndDrain(tester);
    expect(fixture.provider.notes, hasLength(1));
    final committedId = fixture.provider.notes.single.id;
    expect(fixture.provider.notes.single.content, 'confirmed before lock');
    expect(find.byType(NoteEditScreen), findsOneWidget);
    expect(find.text('保存失败，草稿已保留，请重试'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    await _captureScreenshot(tester, fixture, 'save-committed-after-lock');

    fixture.provider.onLocalMutationPersisted = null;
    await _saveAndDrain(tester);
    expect(fixture.store.noteWriteAttempts, 2);
    expect(fixture.provider.notes, hasLength(1));
    expect(fixture.provider.notes.single.id, committedId);
    expect(find.byType(NoteEditScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final layout in [
    (
      name: 'phone-with-keyboard',
      size: const Size(320, 844),
      keyboardInset: 284.0,
    ),
    (
      name: 'landscape-with-keyboard',
      size: const Size(568, 320),
      keyboardInset: 116.0,
    ),
  ]) {
    testWidgets('Note editor remains usable at ${layout.name}', (tester) async {
      I18n.setLocale(AppLocale.en);
      final fixture = await _mountEditor(
        tester,
        size: layout.size,
        textScale: 1.3,
        keyboardInset: layout.keyboardInset,
      );
      await _openEditor(tester);
      await tester.enterText(
        _editorField(),
        'A long first line for a narrow editor\nSecond line\nThird line',
      );
      expect(tester.widget<TextField>(_editorField()).expands, isTrue);
      expect(find.byType(SingleChildScrollView), findsWidgets);
      expect(find.byType(NoteEditScreen), findsOneWidget);
      await _captureScreenshot(tester, fixture, 'layout-${layout.name}');
      if (layout.size.height < 400) {
        final outer = find.byType(Scrollable).first;
        await tester.drag(outer, const Offset(0, -100));
        await _settleFrames(tester);
        expect(
          tester.state<ScrollableState>(outer).position.pixels,
          greaterThan(0),
        );
      }
      await _openManualAttachmentForm(tester);
      expect(_attachmentSubmit().hitTestable(), findsOneWidget);
      await tester.ensureVisible(_attachmentField('note-attachment-type'));
      await _settleFrames(tester);
      expect(
        _attachmentField('note-attachment-type').hitTestable(),
        findsOneWidget,
      );
      await _captureScreenshot(tester, fixture, 'attachment-${layout.name}');
      await tester.tap(find.text('Cancel'));
      await _settleFrames(tester);
      expect(find.byType(NoteEditScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

Finder _openButton() => find.byKey(const ValueKey('open-note-editor'));

Finder _saveButton() => find.byKey(const ValueKey('note-editor-save'));

Finder _editorField() => find.descendant(
  of: find.byType(NoteEditScreen),
  matching: find.byType(TextField),
);

Finder _formatButton(IconData icon) =>
    find.ancestor(of: find.byIcon(icon), matching: find.byType(IconButton));

Finder _previewButton() => _formatButton(Icons.visibility_outlined);

Finder _attachmentButton() => _formatButton(Icons.attach_file);

Finder _attachmentField(String key) => find.byKey(ValueKey<String>(key));

Finder _attachmentSubmit() =>
    find.byKey(const ValueKey<String>('note-attachment-submit'));

Finder _noteCard(String id) => find.byKey(ValueKey<String>('active-$id'));

Finder _libraryCard(String id, {bool archived = false}) =>
    find.byKey(ValueKey<String>((archived ? 'archived-' : 'active-') + id));

String _libraryActionLabel(String action) =>
    I18n.tr(action == 'delete' ? 'action.delete' : 'note.$action');

Future<void> _selectLibraryAction(WidgetTester tester, String action) async {
  await tester.tap(find.byTooltip(I18n.tr('note.more')));
  await _settleFrames(tester);
  await tester.tap(find.text(_libraryActionLabel(action)));
  await _settleFrames(tester);
}

VoidCallback _retainedLibraryAction(
  WidgetTester tester,
  Finder card,
  String action,
) {
  final menuFinder = find.descendant(
    of: card,
    matching: find.byWidgetPredicate((widget) => widget is PopupMenuButton),
  );
  // Read the private enum callback dynamically: widening the widget generic
  // also widens its callback parameter and introduces an invalid runtime cast.
  final dynamic menu = tester.widget(menuFinder);
  final Iterable<dynamic> entries = menu.itemBuilder(
    tester.element(menuFinder),
  );
  final dynamic item = entries.firstWhere(
    (entry) =>
        entry is PopupMenuItem &&
        entry.value.toString().split('.').last == action,
  );
  final dynamic selected = menu.onSelected;
  return () => selected(item.value);
}

Finder _noteCardOpen(String id, String title) => find
    .ancestor(
      of: find.descendant(of: _noteCard(id), matching: find.text(title)),
      matching: find.byType(InkWell),
    )
    .first;

NoteItem _note({
  required String id,
  required String content,
  bool archived = false,
}) {
  final timestamp = DateTime(2026, 10, 15, 12);
  return NoteItem(
    id: id,
    content: content,
    archived: archived,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

Future<_Fixture> _mountEditor(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double textScale = 1,
  double keyboardInset = 0,
  bool useLibraryHome = false,
  List<NoteItem> initialNotes = const <NoteItem>[],
  NoteItem? editorNote,
  PreferencesProvider? preferences,
  ThemeProvider? liveTheme,
}) async {
  final fixture = _Fixture(
    previousPreferencesStore: SharedPreferencesStorePlatform.instance,
    previousFileSelector: FileSelectorPlatform.instance,
  );
  SharedPreferencesStorePlatform.instance = fixture.store;
  if (initialNotes.isNotEmpty) {
    await tester.runAsync(() async {
      for (final note in initialNotes) {
        await fixture.provider.addOrUpdateNotePersisted(note);
      }
    });
  }
  // Use the same real font metrics for behavioral and screenshot runs.
  // The capture flag controls file output only, never the widget tree.
  await tester.runAsync(_loadNoteScreenshotFonts);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() async {
    fixture.store.releaseHold();
    for (final selector in fixture.selectors) {
      if (!selector.release.isCompleted) selector.release.complete(null);
    }
    await _pumpFrames(tester, count: 5);
    await _drainWrites(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.routeGate.dispose();
    fixture.provider.dispose();
    fixture.lock.dispose();
    tester.view.reset();
    SharedPreferencesStorePlatform.instance = fixture.previousPreferencesStore;
    FileSelectorPlatform.instance = fixture.previousFileSelector;
  });

  Widget buildApp(ThemeData theme) => MaterialApp(
    navigatorKey: fixture.navigator,
    navigatorObservers: [fixture.routeGate],
    theme: theme.copyWith(platform: TargetPlatform.iOS),
    builder: (context, child) => RepaintBoundary(
      key: fixture.screenshotBoundary,
      child: ColoredBox(
        color: theme.colorScheme.surfaceContainerLowest,
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            viewInsets: EdgeInsets.only(bottom: keyboardInset),
          ),
          child: child!,
        ),
      ),
    ),
    home: useLibraryHome
        ? const NoteScreen()
        : Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Editor parent'),
                    TextButton(
                      key: const ValueKey('open-note-editor'),
                      onPressed: () => Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => liveTheme == null
                              ? NoteEditScreen(note: editorNote)
                              : BrandRouteSurface(
                                  child: NoteEditScreen(note: editorNote),
                                ),
                        ),
                      ),
                      child: const Text('Open note editor'),
                    ),
                  ],
                ),
              ),
            ),
          ),
  );
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<NoteProvider>.value(value: fixture.provider),
        ChangeNotifierProvider<AppLockProvider>.value(value: fixture.lock),
        if (preferences != null)
          ChangeNotifierProvider<PreferencesProvider>.value(value: preferences),
        if (liveTheme != null)
          ChangeNotifierProvider<ThemeProvider>.value(value: liveTheme),
      ],
      child: liveTheme == null
          ? buildApp(AppBrands.defaultBrand.theme)
          : Consumer<ThemeProvider>(
              builder: (_, current, _) => buildApp(current.brand.theme),
            ),
    ),
  );
  await _settleFrames(tester);
  return fixture;
}

Future<void> _expectLibraryMetadata(
  WidgetTester tester,
  String key, {
  String? pattern,
}) async {
  final card = find.byKey(ValueKey<String>(key));
  final date = find.descendant(
    of: card,
    matching: find.text(
      I18nDateFormat.fullDateTime(DateTime(2026, 10, 15, 12), pattern: pattern),
    ),
  );
  expect(date, findsOneWidget);
  await tester.ensureVisible(date);
  await _settleFrames(tester);
  final text = tester.widget<Text>(date);
  expect(text.maxLines, isNull);
  expect(text.overflow, isNot(TextOverflow.ellipsis));
  expect(text.style!.fontSize, 11);
  final cardRect = tester.getRect(card);
  final dateRect = tester.getRect(date);
  expect(dateRect.left, greaterThanOrEqualTo(cardRect.left));
  expect(dateRect.right, lessThanOrEqualTo(cardRect.right));
  for (final label in ['note.active', 'note.archived']) {
    final text = '${I18n.tr(label)} 1';
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: find.text(text), matching: find.byType(RichText)),
    );
    // Runs using different fallback fonts can have different tight-box tops
    // on the same line. Max-height boxes share the line's vertical bounds.
    final lines = paragraph
        .getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: text.length),
          boxHeightStyle: ui.BoxHeightStyle.max,
        )
        .map((box) => box.top.toStringAsFixed(3))
        .toSet();
    expect(
      lines,
      hasLength(1),
      reason: 'Keep the complete filter label on one line',
    );
  }
  expect(tester.takeException(), isNull);
}

Future<void> _openEditor(WidgetTester tester) async {
  await tester.tap(_openButton());
  await _settleFrames(tester);
  expect(find.byType(NoteEditScreen), findsOneWidget);
}

Future<void> _openAttachmentSheet(WidgetTester tester) async {
  await tester.ensureVisible(_attachmentButton());
  await _settleFrames(tester);
  await tester.tap(_attachmentButton());
  await _settleFrames(tester);
  expect(find.text(I18n.tr('note.attachment.dialog_title')), findsOneWidget);
}

Future<void> _openManualAttachmentForm(WidgetTester tester) async {
  await _openAttachmentSheet(tester);
  await tester.tap(find.text(I18n.tr('note.attachment.add_link')));
  await _settleFrames(tester);
  expect(_attachmentField('note-attachment-location'), findsOneWidget);
}

Future<void> _saveAndDrain(WidgetTester tester) async {
  final callback = tester.widget<IconButton>(_saveButton()).onPressed;
  expect(callback, isNotNull, reason: 'the editor save action is enabled');
  await _invoke(tester, callback!);
  await _drainWrites(tester);
}

Future<void> _invoke(WidgetTester tester, VoidCallback callback) async {
  await tester.runAsync(() async {
    callback();
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });
  await tester.pump();
}

Future<void> _waitForHeldWrite(WidgetTester tester, _NoteStore store) async {
  for (var attempt = 0; attempt < 5; attempt++) {
    if (store.noteWriteStarted.isCompleted) return;
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  expect(store.noteWriteStarted.isCompleted, isTrue, reason: 'note save began');
}

Future<void> _releaseHeldWrite(WidgetTester tester, _Fixture fixture) async {
  fixture.store.releaseHold();
  await _pumpFrames(tester, count: 5);
  await _drainWrites(tester);
}

Future<void> _drainWrites(WidgetTester tester) async {
  var drained = false;
  unawaited(AccountPreferenceWrites.drain().then((_) => drained = true));
  for (var attempt = 0; attempt < 50 && !drained; attempt++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
  }
  await tester.pump();
  expect(drained, isTrue, reason: 'bounded write queue drain');
  await _settleFrames(tester);
}

void _coverAndReturnInSameFrame(WidgetTester tester, _Fixture fixture) {
  final navigator = fixture.navigator.currentState!;
  final revision = fixture.routeGate.routeRevision.value;
  unawaited(
    navigator.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Temporary cover')),
      ),
    ),
  );
  navigator.pop();
  expect(fixture.routeGate.routeRevision.value, revision + 2);
}

// Busy indicators intentionally keep ticking; pump finite route transitions.
Future<void> _settleFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pump();
}

Future<void> _pumpFrames(WidgetTester tester, {required int count}) async {
  for (var frame = 0; frame < count; frame++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _captureScreenshot(
  WidgetTester tester,
  _Fixture fixture,
  String name, {
  String directory = _screenshotDirectory,
}) async {
  if (!_captureScreenshots) return;
  await tester.pump();
  await tester.runAsync(() async {
    final boundary =
        fixture.screenshotBoundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File('$directory/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Future<void> _loadNoteScreenshotFonts() async {
  await loadWidgetPolishScreenshotFonts();
  // Explicit styles in the real brand theme retain these family names.
  final latin = ByteData.sublistView(
    File('assets/fonts/DejaVuSans.ttf').readAsBytesSync(),
  );
  for (final family in ['sans-serif', 'DejaVu Sans', 'Roboto']) {
    await (FontLoader(family)..addFont(Future.value(latin))).load();
  }
  final chinese = ByteData.sublistView(
    File('assets/fonts/DroidSansFallbackFull.ttf').readAsBytesSync(),
  );
  for (final family in const [
    'PingFang SC',
    'Hiragino Sans GB',
    'Noto Sans CJK SC',
    'Source Han Sans SC',
    'Microsoft YaHei',
    'WenQuanYi Micro Hei',
    'DroidSansFallbackFull',
  ]) {
    await (FontLoader(family)..addFont(Future.value(chinese))).load();
  }
  await PaintingBinding.instance.handleSystemMessage(<String, dynamic>{
    'type': 'fontsChange',
  });
}

class _Fixture {
  _Fixture({
    required this.previousPreferencesStore,
    required this.previousFileSelector,
  });

  final SharedPreferencesStorePlatform previousPreferencesStore;
  final FileSelectorPlatform previousFileSelector;
  final NoteProvider provider = NoteProvider();
  final _EditorLock lock = _EditorLock();
  final _NoteStore store = _NoteStore();
  final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
  final AppAccessRouteGate routeGate = AppAccessRouteGate();
  final GlobalKey screenshotBoundary = GlobalKey();
  final List<_DeferredFileSelector> selectors = [];

  void installFileSelector(_DeferredFileSelector selector) {
    selectors.add(selector);
    FileSelectorPlatform.instance = selector;
  }
}

class _NoteStore extends InMemorySharedPreferencesStore {
  _NoteStore() : super.withData(<String, Object>{});

  int noteWriteAttempts = 0;
  bool holdNextNoteWrite = false;
  bool failNextNoteWrite = false;
  bool throwOnNoteFailure = false;
  bool failNextTombstoneWrite = false;
  Completer<void> noteWriteStarted = Completer<void>();
  Completer<void> noteWriteRelease = Completer<void>();

  void armHold() {
    holdNextNoteWrite = true;
    noteWriteStarted = Completer<void>();
    noteWriteRelease = Completer<void>();
  }

  void releaseHold() {
    if (!noteWriteRelease.isCompleted) noteWriteRelease.complete();
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == 'flutter.duoyi_notes') {
      noteWriteAttempts++;
      if (holdNextNoteWrite) {
        holdNextNoteWrite = false;
        noteWriteStarted.complete();
        await noteWriteRelease.future;
      }
      if (failNextNoteWrite) {
        failNextNoteWrite = false;
        if (throwOnNoteFailure) {
          throwOnNoteFailure = false;
          throw StateError('injected note persistence failure');
        }
        return false;
      }
    }
    if (key == 'flutter.sync_deleted_items' && failNextTombstoneWrite) {
      failNextTombstoneWrite = false;
      return false;
    }
    return super.setValue(type, key, value);
  }
}

class _EditorLock extends AppLockProvider {
  bool _locked = false;
  int _generation = 0;

  @override
  bool get isLocked => _locked;

  @override
  int get accessGeneration => _generation;

  void setLocked(bool locked) {
    if (_locked == locked) return;
    _locked = locked;
    _generation++;
    notifyListeners();
  }
}

class _DeferredFileSelector extends FileSelectorPlatform {
  final Completer<void> opened = Completer<void>();
  final Completer<XFile?> release = Completer<XFile?>();
  int openCount = 0;

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) {
    openCount++;
    if (!opened.isCompleted) opened.complete();
    return release.future;
  }
}

bool get _captureScreenshots => Platform.environment[_captureEnvKey] == '1';

void _registerAttachmentLiveThemeTests() {
  for (final initialBrand in ['defaultBrand', 'liquidGlass']) {
    for (final manualForm in [false, true]) {
      final modalName = manualForm ? 'form' : 'chooser';
      testWidgets(
        'Note attachment live theme $initialBrand $modalName retains route and draft',
        (tester) async {
          SharedPreferences.setMockInitialValues({
            'active_brand': initialBrand,
            'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
            'theme_shop_state': jsonEncode({
              'activeBrand': initialBrand,
              'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
            }),
          });
          late ThemeProvider theme;
          await tester.runAsync(() async {
            theme = ThemeProvider();
            await theme.loadFromStorage();
          });
          addTearDown(theme.dispose);
          final fixture = await _mountEditor(tester, liveTheme: theme);
          await _openEditor(tester);
          expect(find.byType(BrandRouteSurface), findsOneWidget);
          await tester.enterText(_editorField(), 'Retained editor draft 未保存');
          final editorState = tester.state(find.byType(NoteEditScreen));
          final editorController = tester
              .widget<TextField>(_editorField())
              .controller!;
          editorController.selection = const TextSelection(
            baseOffset: 1,
            extentOffset: 5,
          );
          if (manualForm) {
            await _openManualAttachmentForm(tester);
          } else {
            await _openAttachmentSheet(tester);
          }
          final modal = find.byType(manualForm ? AppDialog : AppModalSheet);
          final modalElement = tester.element(modal);
          final modalRoute = ModalRoute.of(modalElement);
          TextEditingController? name;
          TextEditingController? location;
          if (manualForm) {
            await tester.enterText(
              _attachmentField('note-attachment-name'),
              'Unsaved guide',
            );
            name = tester
                .widget<TextField>(_attachmentField('note-attachment-name'))
                .controller;
            location = tester
                .widget<TextField>(_attachmentField('note-attachment-location'))
                .controller;
            await tester.tap(_attachmentSubmit());
            await _settleFrames(tester);
            expect(
              tester
                  .widget<TextField>(
                    _attachmentField('note-attachment-location'),
                  )
                  .decoration!
                  .errorText,
              NoteEditorUiCopy.requiredLocation,
            );
          }
          final otherBrand = initialBrand == 'defaultBrand'
              ? 'liquidGlass'
              : 'defaultBrand';
          var stage = 0;
          for (final brand in [initialBrand, otherBrand, initialBrand]) {
            await tester.runAsync(() async {
              expect(await theme.setBrand(brand), isTrue);
              await AccountPreferenceWrites.drain().timeout(
                const Duration(seconds: 5),
              );
            });
            await _settleFrames(tester);
            expect(tester.element(modal), same(modalElement));
            expect(ModalRoute.of(tester.element(modal)), same(modalRoute));
            expect(
              Theme.of(tester.element(modal)).colorScheme,
              theme.brand.theme.colorScheme,
              reason: 'The opened attachment $modalName must follow $brand',
            );
            expect(
              appSurfaceStyleOf(tester.element(modal)),
              theme.brand.theme.extension<AppSurfaceStyle>(),
            );
            expect(
              tester.state(find.byType(NoteEditScreen)),
              same(editorState),
            );
            expect(editorController.text, 'Retained editor draft 未保存');
            expect(
              editorController.selection,
              const TextSelection(baseOffset: 1, extentOffset: 5),
            );
            if (manualForm) {
              expect(
                tester
                    .widget<TextField>(_attachmentField('note-attachment-name'))
                    .controller,
                same(name),
              );
              expect(
                tester
                    .widget<TextField>(
                      _attachmentField('note-attachment-location'),
                    )
                    .controller,
                same(location),
              );
              expect(name!.text, 'Unsaved guide');
              expect(location!.text, isEmpty);
              expect(
                tester
                    .widget<TextField>(
                      _attachmentField('note-attachment-location'),
                    )
                    .decoration!
                    .errorText,
                NoteEditorUiCopy.requiredLocation,
              );
            }
            expect(tester.takeException(), isNull);
            if (stage < 2) {
              await _captureScreenshot(
                tester,
                fixture,
                'attachment-$initialBrand-$modalName-$stage-$brand',
                directory:
                    'evidence/screenshots/note-attachment-live-20261025-v710',
              );
            }
            stage++;
          }
          I18n.setLocale(AppLocale.en);
          await _settleFrames(tester);
          expect(find.text('Add attachment'), findsOneWidget);
          await _captureScreenshot(
            tester,
            fixture,
            'attachment-$initialBrand-$modalName-en',
            directory:
                'evidence/screenshots/note-attachment-live-20261025-v710',
          );
          if (manualForm) {
            expect(name!.text, 'Unsaved guide');
            expect(
              tester
                  .widget<TextField>(
                    _attachmentField('note-attachment-location'),
                  )
                  .decoration!
                  .errorText,
              NoteEditorUiCopy.requiredLocation,
            );
            await tester.enterText(
              _attachmentField('note-attachment-location'),
              'https://example.test/draft.pdf',
            );
            await _settleFrames(tester);
            expect(
              tester
                  .widget<TextField>(
                    _attachmentField('note-attachment-location'),
                  )
                  .decoration!
                  .errorText,
              isNull,
            );
            await tester.tap(find.text('Cancel'));
          } else {
            fixture.navigator.currentState!.pop();
          }
          await _settleFrames(tester);
          expect(modal, findsNothing);
          expect(editorController.text, 'Retained editor draft 未保存');
          expect(fixture.provider.notes, isEmpty);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
