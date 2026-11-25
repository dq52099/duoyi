// ignore_for_file: depend_on_referenced_packages

// Prepared commit contract; not compiled or executed during preparation.
// Mounts the production entrance using the retained integration fixture's
// provider/BrandRouteSurface structure. LocationReminderProvider is never mocked.
// Baseline captures precede assertions about the missing retained-save behavior.
// The runner owns disk admission, the serial lock, and live resource guarding.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/notification_ui_copy.dart';
import 'package:duoyi/models/location_reminder.dart';
import 'package:duoyi/providers/location_reminder_provider.dart';
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/integrations_screen.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/calendar_sync_service.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/weekly_review_screenshot_font.dart';

const _key = 'duoyi_location_reminders_v1';
const _platformKey = 'flutter.$_key';
const _timeout = Duration(seconds: 5);
const _open = ValueKey('open-location-add-commit-fixture');
const _literalTitle = '  Literal 用户 place / keep spaces  ';
const _draft = [_literalTitle, '  +39.904200  ', '  116.407400  ', '  00250  '];
const _invalidDraft = ['', 'north 39.9042', 'east 116.4074', '0'];

final _dialog = find.byType(AppDialog);
final _evidenceRoot = Platform.environment['DUOYI_THEME_DIALOG_EVIDENCE_DIR'];
final _runName =
    'integrations-location-add-commit-'
    '${DateTime.now().toUtc().microsecondsSinceEpoch}-$pid';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final brand in ['defaultBrand', 'liquidGlass']) {
    testWidgets('$brand pending add retains its modal until durable commit', (
      tester,
    ) async {
      final f = await _mount(tester, brand, 'pending-commit');
      final semantics = tester.ensureSemantics();
      try {
        await _openDraft(tester, f);
        final values = await _enterDraft(tester, _draft);
        final element = tester.element(_dialog);
        final route = ModalRoute.of(element)!;
        final held = f.store.holdNext();
        final submit = _submitCallback(tester);
        submit();
        // Exercise a callback queued before the first repaint as well as the
        // visible button after repaint. Both must be unable to enqueue another add.
        submit();
        await _until(tester, () => held.started.isCompleted, 'write started');
        await f.capture(tester, 'held-before-assertion');
        final chineseWaiting = _expectBusyPresentation(tester);
        _expectDraft(tester, values);
        expect(tester.element(_dialog), same(element));
        expect(ModalRoute.of(tester.element(_dialog)), same(route));
        expect(_submitButton(tester).onPressed, isNull);
        expect(f.store.draftAttempts, hasLength(1));
        expect(f.locations.reminders.map((r) => r.id), ['existing']);
        expect(await f.store.diskRaw(), f.originalRaw);
        expect(f.persisted, 0);

        await f.switchPresentation(tester);
        await f.capture(tester, 'held-live-en-other-brand');
        expect(_expectBusyPresentation(tester), isNot(chineseWaiting));
        _expectDraft(tester, values);
        expect(ModalRoute.of(tester.element(_dialog)), same(route));
        _expectDialogTheme(tester, f);
        expect(_submitButton(tester).onPressed, isNull);
        submit();
        await _frames(tester);
        expect(f.store.draftAttempts, hasLength(1));
        expect(f.persisted, 0);

        held.release();
        await f.drain(tester);
        await f.capture(tester, 'acknowledged');
        expect(_dialog, findsNothing);
        expect(_busyIndicator(), findsNothing);
        await _expectCommitted(f, f.store.draftAttempts.single);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });

    for (final failure in [
      _Failure.returnsFalse,
      _Failure.throwsBeforeWrite,
      _Failure.writeThenThrow,
    ]) {
      testWidgets('$brand ${failure.name} retains a draft for explicit retry', (
        tester,
      ) async {
        final f = await _mount(tester, brand, 'retry-${failure.name}');
        final semantics = tester.ensureSemantics();
        try {
          await _openDraft(tester, f);
          final values = await _enterDraft(tester, _draft);
          final route = ModalRoute.of(tester.element(_dialog))!;
          final held = f.store.holdNext(failure: failure);
          _submitCallback(tester)();
          await _until(tester, () => held.started.isCompleted, 'write started');
          await f.capture(tester, 'held');
          _expectBusyPresentation(tester);
          held.release();
          await f.drain(tester);
          await f.capture(tester, 'rejected-before-assertion');
          _expectIdlePresentation(tester);

          _expectDraft(tester, values);
          expect(ModalRoute.of(tester.element(_dialog)), same(route));
          expect(tester.takeException(), isNull);
          expect(f.locations.reminders.map((r) => r.id), ['existing']);
          expect(await f.store.diskRaw(), f.originalRaw);
          expect(f.prefs.getString(_key), f.originalRaw);
          expect(f.persisted, 0);
          expect(f.store.draftAttempts, hasLength(1));
          final rejected = Map<String, dynamic>.from(
            f.store.draftAttempts.single,
          );
          final chineseFeedback = _feedback(tester);
          expect(chineseFeedback, isNotEmpty);
          expect(chineseFeedback, matches(RegExp(r'[\u3400-\u9fff]')));
          expect(chineseFeedback, isNot(contains('PRIVATE')));
          _expectExplicitRetry(tester);

          await f.switchPresentation(tester);
          await f.capture(tester, 'rejected-live-en-other-brand');
          _expectIdlePresentation(tester);
          _expectDraft(tester, values);
          _expectDialogTheme(tester, f);
          final englishFeedback = _feedback(tester);
          expect(englishFeedback, isNotEmpty);
          expect(englishFeedback, isNot(chineseFeedback));
          expect(englishFeedback, isNot(matches(RegExp(r'[\u3400-\u9fff]'))));
          expect(englishFeedback, isNot(contains('StateError')));
          expect(englishFeedback, isNot(contains('PRIVATE')));
          expect(
            f.store.draftAttempts,
            hasLength(1),
            reason: 'no automatic retry',
          );
          _expectExplicitRetry(tester);

          // Reloading acknowledged data must not replace the retained new draft.
          await tester.runAsync(() async {
            await f.prefs.reload();
            await f.locations.loadFromStorage().timeout(_timeout);
          });
          await _frames(tester);
          _expectDraft(tester, values);
          final retry = f.store.holdNext();
          _submitCallback(tester)();
          await _until(
            tester,
            () => retry.started.isCompleted,
            'retry started',
          );
          await f.capture(tester, 'explicit-retry-held');
          _expectBusyPresentation(tester);
          _expectDraft(tester, values);
          expect(_submitButton(tester).onPressed, isNull);
          expect(f.store.draftAttempts, hasLength(2));
          final retried = f.store.draftAttempts.last;
          for (final field in ['id', 'createdAt', 'updatedAt']) {
            expect(
              retried[field],
              rejected[field],
              reason: 'stable draft $field',
            );
          }
          retry.release();
          await f.drain(tester);
          await f.capture(tester, 'explicit-retry-committed');
          expect(_dialog, findsNothing);
          expect(_busyIndicator(), findsNothing);
          await _expectCommitted(f, rejected);
          expect(f.store.draftAttempts, hasLength(2));
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      });
    }

    for (final view in _View.values) {
      testWidgets('$brand ${view.name} retained field errors translate live', (
        tester,
      ) async {
        final f = await _mount(tester, brand, 'validation-${view.name}');
        await _openDraft(tester, f);
        final values = await _enterDraft(tester, _invalidDraft);
        f.setView(tester, view);
        await _frames(tester);
        _submitCallback(tester)();
        await _frames(tester);
        await f.capture(tester, 'invalid-zh-before-assertion');
        _expectDraft(tester, values, trigger: LocationTrigger.leave);
        expect(_fieldErrors(tester), [
          '请填写提醒标题',
          '请输入有效纬度',
          '请输入有效经度',
          '请输入有效半径',
        ]);
        expect(f.store.draftAttempts, isEmpty);

        await f.switchPresentation(tester);
        await f.capture(tester, 'invalid-en-other-brand-before-assertion');
        _expectDraft(tester, values, trigger: LocationTrigger.leave);
        expect(_fieldErrors(tester), [
          'Please enter a reminder title',
          'Please enter a valid latitude',
          'Please enter a valid longitude',
          'Please enter a valid radius',
        ]);
        _expectDialogTheme(tester, f);
        await _expectReachableActions(tester);
        expect(tester.takeException(), isNull);
        expect(f.store.draftAttempts, isEmpty);
        expect(f.persisted, 0);
      });
    }

    testWidgets(
      '$brand indeterminate add keeps identity through reconciliation',
      (tester) async {
        final f = await _mount(tester, brand, 'indeterminate-reconciliation');
        await _openDraft(tester, f);
        final values = await _enterDraft(tester, _draft);
        f.store.failures.addAll([
          _Failure.writeThenFalse,
          _Failure.returnsFalse, // Restoration of the existing key also fails.
        ]);
        _submitCallback(tester)();
        await f.drain(tester);
        await f.capture(tester, 'indeterminate-before-assertion');
        _expectDraft(tester, values);
        expect(tester.takeException(), isNull);
        expect(f.locations.storageNeedsReconciliation, isTrue);
        expect(f.locations.reminders.map((r) => r.id), ['existing']);
        expect(f.persisted, 0);
        final issued = Map<String, dynamic>.from(f.store.draftAttempts.first);
        await f.switchPresentation(tester);
        await f.capture(tester, 'indeterminate-live-en-other-brand');
        _expectDraft(tester, values);
        _expectDialogTheme(tester, f);

        // Exercise the existing main-owned recovery API without inventing a new
        // frontend recovery label or automatically replaying the user's add.
        final attemptsBeforeReconciliation = f.store.draftAttempts.length;
        await tester.runAsync(
          () => f.locations.reconcileStorage().timeout(_timeout),
        );
        await _frames(tester);
        expect(f.locations.storageNeedsReconciliation, isFalse);
        expect(await f.store.diskRaw(), f.originalRaw);
        expect(f.store.draftAttempts, hasLength(attemptsBeforeReconciliation));
        expect(f.persisted, 0);
        _expectDraft(tester, values);
        _expectExplicitRetry(tester);
        _submitCallback(tester)();
        await f.drain(tester);
        await f.capture(tester, 'reconciled-explicit-retry');
        expect(_dialog, findsNothing);
        await _expectCommitted(f, issued);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '$brand failed recovery retains localized draft and can recover again',
      (tester) async {
        final f = await _mount(tester, brand, 'ui-recovery-failures');
        final semantics = tester.ensureSemantics();
        try {
          await _openDraft(tester, f);
          final values = await _enterDraft(tester, _draft);
          final element = tester.element(_dialog);
          final route = ModalRoute.of(element)!;
          f.store.failures.addAll([
            _Failure.writeThenFalse,
            _Failure.returnsFalse,
          ]);
          await _tapModalAction(tester, _primary());
          await f.drain(tester);
          await f.capture(tester, 'indeterminate-ui-before-recovery');
          _expectIdlePresentation(tester);
          _expectRetainedRecoveryDraft(tester, values, element, route);
          expect(f.locations.storageNeedsReconciliation, isTrue);
          expect(f.locations.reminders.map((r) => r.id), ['existing']);
          expect(f.persisted, 0);
          expect(f.store.failures, isEmpty);
          expect(f.store.draftAttempts, hasLength(1));
          expect(_submitButton(tester).onPressed, isNull);
          _expectSafeRecoveryFeedback(tester);
          expect(tester.takeException(), isNull);
          final issued = Map<String, dynamic>.from(
            f.store.draftAttempts.single,
          );
          expect(await f.store.diskRows(), [f.existing.toJson(), issued]);
          final uncertainRaw = await f.store.diskRaw();

          for (final failure in [
            _Failure.returnsFalse,
            _Failure.throwsBeforeWrite,
          ]) {
            final writesBeforeRecovery = f.store.snapshots.length;
            final recovery = f.store.holdNext(failure: failure);
            expect(_recoveryButton(tester).onPressed, isNotNull);
            await _tapModalAction(tester, _recovery());
            await _until(
              tester,
              () => recovery.started.isCompleted,
              'recovery started',
            );
            await f.capture(tester, 'ui-recovery-${failure.name}-held');
            _expectBusyPresentation(tester);
            _expectRetainedRecoveryDraft(tester, values, element, route);
            expect(_recoveryButton(tester).onPressed, isNull);
            expect(_submitButton(tester).onPressed, isNull);
            expect(f.store.snapshots, hasLength(writesBeforeRecovery + 1));
            expect(f.store.snapshots.last, [f.existing.toJson()]);
            expect(f.store.draftAttempts, hasLength(1));
            expect(await f.store.diskRaw(), uncertainRaw);
            expect(f.persisted, 0);
            recovery.release();
            await f.drain(tester);
            await f.capture(tester, 'ui-recovery-${failure.name}-rejected');
            _expectIdlePresentation(tester);
            _expectRetainedRecoveryDraft(tester, values, element, route);
            expect(f.locations.storageNeedsReconciliation, isTrue);
            expect(await f.store.diskRaw(), uncertainRaw);
            expect(f.locations.reminders.map((r) => r.id), ['existing']);
            expect(f.store.snapshots, hasLength(writesBeforeRecovery + 1));
            expect(f.store.draftAttempts, hasLength(1));
            expect(f.persisted, 0);
            expect(_recoveryButton(tester).onPressed, isNotNull);
            expect(_submitButton(tester).onPressed, isNull);
            // A rejected recovery retains the uncertain-state guidance; it need
            // not invent a different message for the false/throw failure modes.
            final feedback = _expectSafeRecoveryFeedback(tester);
            expect(tester.takeException(), isNull);

            if (failure == _Failure.returnsFalse) {
              await f.switchPresentation(tester);
              await f.capture(tester, 'ui-recovery-failed-live-en-other-brand');
              _expectIdlePresentation(tester);
              _expectRetainedRecoveryDraft(tester, values, element, route);
              _expectDialogTheme(tester, f);
              expect(_expectSafeRecoveryFeedback(tester), isNot(feedback));
              expect(_recoveryButton(tester).onPressed, isNotNull);
              expect(_submitButton(tester).onPressed, isNull);
              expect(f.store.snapshots, hasLength(writesBeforeRecovery + 1));
              expect(f.store.draftAttempts, hasLength(1));
              expect(f.persisted, 0);
            }
          }

          // The actual third recovery tap starts a held restoration. Retained
          // callback replay checks the guard before the first repaint.
          final writesBeforeRecovery = f.store.snapshots.length;
          final queuedRecovery = _recoveryButton(tester).onPressed!;
          final recovery = f.store.holdNext();
          await _tapModalAction(tester, _recovery());
          queuedRecovery();
          await _until(
            tester,
            () => recovery.started.isCompleted,
            'successful recovery started',
          );
          await f.capture(tester, 'ui-recovery-again-held');
          _expectBusyPresentation(tester);
          _expectRetainedRecoveryDraft(tester, values, element, route);
          _expectDialogTheme(tester, f);
          _expectSafeRecoveryFeedback(tester);
          expect(_recoveryButton(tester).onPressed, isNull);
          expect(_submitButton(tester).onPressed, isNull);
          expect(f.locations.storageNeedsReconciliation, isTrue);
          expect(await f.store.diskRaw(), uncertainRaw);
          expect(f.locations.reminders.map((r) => r.id), ['existing']);
          expect(f.store.snapshots, hasLength(writesBeforeRecovery + 1));
          expect(f.store.snapshots.last, [f.existing.toJson()]);
          expect(f.store.draftAttempts, hasLength(1));
          expect(f.persisted, 0);
          recovery.release();
          await f.drain(tester);
          await f.capture(tester, 'ui-recovery-again-acknowledged-no-replay');
          _expectIdlePresentation(tester);
          _expectRetainedRecoveryDraft(tester, values, element, route);
          expect(f.locations.storageNeedsReconciliation, isFalse);
          expect(await f.store.diskRaw(), f.originalRaw);
          expect(f.prefs.getString(_key), f.originalRaw);
          expect(f.locations.reminders.map((r) => r.id), ['existing']);
          expect(f.store.snapshots, hasLength(writesBeforeRecovery + 1));
          expect(f.store.snapshots.last, [f.existing.toJson()]);
          expect(f.store.draftAttempts, hasLength(1));
          expect(f.persisted, 0);
          expect(_recovery(), findsNothing);
          _expectRecoveryRetry(tester);
          await _frames(tester);
          expect(await f.store.diskRaw(), f.originalRaw);
          expect(f.store.snapshots, hasLength(writesBeforeRecovery + 1));
          expect(f.store.draftAttempts, hasLength(1));
          expect(f.persisted, 0);

          final retry = f.store.holdNext();
          await _tapModalAction(tester, _primary());
          await _until(
            tester,
            () => retry.started.isCompleted,
            'separate retry started',
          );
          await f.capture(tester, 'ui-recovery-failures-separate-retry-held');
          _expectBusyPresentation(tester);
          _expectRetainedRecoveryDraft(tester, values, element, route);
          expect(_submitButton(tester).onPressed, isNull);
          expect(f.store.draftAttempts, hasLength(2));
          expect(f.store.draftAttempts.last, issued);
          expect(await f.store.diskRaw(), f.originalRaw);
          expect(f.persisted, 0);
          retry.release();
          await f.drain(tester);
          await _until(
            tester,
            () => _dialog.evaluate().isEmpty,
            'owned modal closed',
          );
          await f.capture(
            tester,
            'ui-recovery-failures-separate-retry-committed',
          );
          expect(_dialog, findsNothing);
          expect(_busyIndicator(), findsNothing);
          expect(f.store.draftAttempts, hasLength(2));
          expect(f.store.draftAttempts.last, issued);
          await _expectCommitted(f, issued);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );

    for (final invalidation in _Invalidation.values) {
      testWidgets('$brand retained Save rejects ${invalidation.name}', (
        tester,
      ) async {
        final f = await _mount(
          tester,
          brand,
          'stale-save-${invalidation.name}',
        );
        await _openDraft(tester, f);
        await _enterDraft(tester, _draft);
        final staleSave = _submitCallback(tester);
        await f.invalidate(tester, invalidation);
        staleSave();
        await f.drain(tester);
        await f.capture(tester, 'invalidated-before-assertion');
        expect(f.store.draftAttempts, isEmpty);
        expect(await f.store.diskRaw(), f.originalRaw);
        expect(f.persisted, 0);
        expect(
          f.locations.reminders.any((r) => r.title == _literalTitle.trim()),
          isFalse,
        );
        expect(
          f.current.value.reminders.any((r) => r.title == _literalTitle.trim()),
          isFalse,
        );
        expect(find.byType(SnackBar), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    for (final invalidation in [
      _Invalidation.parent,
      _Invalidation.account,
      _Invalidation.replacement,
    ]) {
      for (final reject in [false, true]) {
        testWidgets(
          '$brand pending ${reject ? 'rejection' : 'acknowledgement'} '
          'rejects ${invalidation.name} origin',
          (tester) async {
            final f = await _mount(
              tester,
              brand,
              'pending-${invalidation.name}-${reject ? 'reject' : 'ack'}',
            );
            await _openDraft(tester, f);
            await _enterDraft(tester, _draft);
            final held = f.store.holdNext(
              failure: reject ? _Failure.returnsFalse : null,
            );
            _submitCallback(tester)();
            await _until(
              tester,
              () => held.started.isCompleted,
              'write started',
            );
            await f.capture(tester, 'held');
            await f.invalidate(tester, invalidation);
            // A covering route also detects a stale continuation popping an
            // unrelated route or showing its failure on a new feedback host.
            final cover = MaterialPageRoute<void>(
              builder: (_) =>
                  const Scaffold(body: Text('Unrelated covering route')),
            );
            unawaited(f.navigator.currentState!.push<void>(cover));
            await _frames(tester);
            var replacementEffects = 0;
            Object? replacementError;
            Future<void>? replacementWrite;
            LocationReminder? replacementRow;
            if (invalidation == _Invalidation.replacement) {
              // Leave the outgoing instance alive and queue a replacement's
              // write behind its held transaction. Rollback must finish first.
              final replacement = f.current.value;
              replacement.onLocalMutationPersisted = () => replacementEffects++;
              replacementRow = LocationReminder(
                id: 'replacement-owned',
                title: 'Replacement owns this row',
                latitude: 1,
                longitude: 2,
                createdAt: DateTime.utc(2026, 11, 9, 12),
                updatedAt: DateTime.utc(2026, 11, 9, 12),
              );
              replacementWrite = replacement
                  .add(replacementRow)
                  .then<void>(
                    (_) {},
                    onError: (Object error, StackTrace stack) {
                      replacementError = error;
                    },
                  );
              await _frames(tester);
              expect(replacementEffects, 0);
              expect(replacement.reminders, isEmpty);
              expect(await f.store.diskRaw(), f.originalRaw);
            }
            held.release();
            await f.drain(tester);
            await f.capture(tester, 'invalidated-completion-before-assertion');
            expect(cover.isCurrent, isTrue);
            expect(find.text('Unrelated covering route'), findsOneWidget);
            expect(find.byType(SnackBar), findsNothing);
            expect(f.persisted, 0);
            expect(
              f.locations.reminders.any((r) => r.title == _literalTitle.trim()),
              isFalse,
            );
            expect(tester.takeException(), isNull);

            if (invalidation == _Invalidation.replacement) {
              final replacement = f.current.value;
              final next = replacementRow!;
              await tester.runAsync(() => replacementWrite!.timeout(_timeout));
              expect(replacementError, isNull);
              expect(replacementEffects, 1);
              expect(replacement.reminders.map((r) => r.id), [
                'existing',
                next.id,
              ]);
              expect((await f.store.diskRows()).map((r) => r['id']), [
                'existing',
                next.id,
              ]);
              expect(f.persisted, 0);
            } else {
              expect(await f.store.diskRaw(), f.originalRaw);
            }
          },
        );
      }
    }
  }
}

enum _Invalidation { parent, account, replacement, storageReset }

enum _Failure {
  returnsFalse,
  throwsBeforeWrite,
  writeThenFalse,
  writeThenThrow,
}

enum _View {
  normal(Size(390, 844), 1, 0),
  enlargedPortrait(Size(320, 844), 1.6, 260),
  shortLandscape(Size(740, 400), 1.4, 140);

  const _View(this.size, this.scale, this.keyboard);
  final Size size;
  final double scale;
  final double keyboard;
}

Future<void> _frames(WidgetTester tester) async {
  // Do not pumpAndSettle while a held save can display an indeterminate spinner.
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _until(
  WidgetTester tester,
  bool Function() done,
  String reason,
) async {
  for (var i = 0; i < 40 && !done(); i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(done(), isTrue, reason: reason);
}

Finder _fields() =>
    find.descendant(of: _dialog, matching: find.byType(TextField));
Finder _primary() =>
    find.descendant(of: _dialog, matching: find.byType(FilledButton));
FilledButton _submitButton(WidgetTester tester) =>
    tester.widget<FilledButton>(_primary());
VoidCallback _submitCallback(WidgetTester tester) =>
    _submitButton(tester).onPressed!;

Finder _recovery() => find.descendant(
  of: _dialog,
  matching: find.widgetWithText(
    OutlinedButton,
    NotificationUiCopy.isEn ? 'Recover Storage' : '恢复存储',
  ),
);

OutlinedButton _recoveryButton(WidgetTester tester) =>
    tester.widget<OutlinedButton>(_recovery());

Finder _busyIndicator() => find.descendant(
  of: _dialog,
  matching: find.byType(CircularProgressIndicator),
);

TextButton _cancelButton(WidgetTester tester) => tester.widget<TextButton>(
  find.descendant(
    of: _dialog,
    matching: find.widgetWithText(TextButton, I18n.tr('action.cancel')),
  ),
);

String _expectBusyPresentation(WidgetTester tester) {
  final indicator = _busyIndicator();
  expect(indicator, findsOneWidget);
  expect(indicator.hitTestable(), findsOneWidget);
  final size = tester.view.physicalSize / tester.view.devicePixelRatio;
  final keyboard = MediaQuery.viewInsetsOf(tester.element(_dialog)).bottom;
  final viewport = Rect.fromLTWH(0, 0, size.width, size.height - keyboard);
  final rect = tester.getRect(indicator);
  expect(rect.size.isEmpty, isFalse);
  expect(viewport.inflate(.1).contains(rect.topLeft), isTrue);
  expect(viewport.inflate(.1).contains(rect.bottomRight), isTrue);

  // Waiting can be announced by the indicator, an enclosing semantics node,
  // or visible status text. Inspect the dialog's accessible subtree without
  // prescribing the presentation's node placement or exact wording.
  final labels = <String>{};
  void collectLabels(SemanticsNode node) {
    labels.addAll(node.getSemanticsData().label.split('\n'));
    node.visitChildren((child) {
      collectLabels(child);
      return true;
    });
  }

  collectLabels(tester.getSemantics(_dialog));
  final ordinaryLabels = <String>{
    NotificationUiCopy.newLocationReminderTitle,
    NotificationUiCopy.reminderTitleLabel,
    NotificationUiCopy.latitudeLabel,
    NotificationUiCopy.longitudeLabel,
    NotificationUiCopy.radiusMetersLabel,
    NotificationUiCopy.triggerDirectionLabel,
    NotificationUiCopy.triggerEnter,
    NotificationUiCopy.triggerLeave,
    I18n.tr('action.cancel'),
    I18n.tr('action.save'),
    I18n.tr('action.retry'),
    'Recover Storage',
    '恢复存储',
    'Storage state is uncertain. Please recover storage before retrying.',
    '存储状态异常，重试前请先恢复存储',
    'Failed to save reminder. Please retry.',
    '保存提醒失败，请重试',
    ..._draft.map((value) => value.trim()),
  };
  final waiting = labels
      .map((label) => label.trim())
      .where((label) => label.isNotEmpty && !ordinaryLabels.contains(label))
      .join('\n');
  expect(waiting, isNotEmpty, reason: 'waiting is accessible beyond captions');
  final chinese = matches(RegExp(r'[\u3400-\u9fff]'));
  expect(waiting, NotificationUiCopy.isEn ? isNot(chinese) : chinese);

  expect(_submitButton(tester).onPressed, isNull);
  expect(_cancelButton(tester).onPressed, isNull);
  final chips = tester.widgetList<ChoiceChip>(
    find.descendant(of: _dialog, matching: find.byType(ChoiceChip)),
  );
  expect(chips, hasLength(2));
  expect(chips.map((chip) => chip.onSelected), everyElement(isNull));
  if (_recovery().evaluate().isNotEmpty) {
    expect(_recoveryButton(tester).onPressed, isNull);
  }
  return waiting;
}

void _expectIdlePresentation(WidgetTester tester) {
  expect(_busyIndicator(), findsNothing);
  expect(_cancelButton(tester).onPressed, isNotNull);
  final chips = tester.widgetList<ChoiceChip>(
    find.descendant(of: _dialog, matching: find.byType(ChoiceChip)),
  );
  expect(chips, hasLength(2));
  expect(chips.map((chip) => chip.onSelected), everyElement(isNotNull));
}

Future<void> _tapModalAction(WidgetTester tester, Finder action) async {
  expect(action, findsOneWidget);
  expect(tester.widget<ButtonStyleButton>(action).onPressed, isNotNull);
  await tester.ensureVisible(action);
  await _frames(tester);
  expect(action.hitTestable(), findsOneWidget);
  final size = tester.view.physicalSize / tester.view.devicePixelRatio;
  final keyboard = MediaQuery.viewInsetsOf(tester.element(_dialog)).bottom;
  final viewport = Rect.fromLTWH(0, 0, size.width, size.height - keyboard);
  final rect = tester.getRect(action);
  expect(viewport.inflate(.1).contains(rect.topLeft), isTrue);
  expect(viewport.inflate(.1).contains(rect.bottomRight), isTrue);
  await tester.tap(action);
}

void _expectRetainedRecoveryDraft(
  WidgetTester tester,
  List<TextEditingValue> values,
  Element element,
  ModalRoute<dynamic> route,
) {
  _expectDraft(tester, values);
  expect(tester.element(_dialog), same(element));
  expect(ModalRoute.of(tester.element(_dialog)), same(route));
  expect(route.isActive, isTrue);
  expect(route.isCurrent, isTrue);
}

void _expectRecoveryRetry(WidgetTester tester) {
  expect(_submitButton(tester).onPressed, isNotNull);
  expect(
    find.descendant(
      of: _primary(),
      matching: find.text(I18n.tr('action.retry')),
    ),
    findsOneWidget,
    reason: 'recovery enables a separate explicit Retry',
  );
}

String _expectSafeRecoveryFeedback(WidgetTester tester) {
  // The recovery caption itself must not pass a nonempty feedback assertion.
  final feedback = _feedback(tester)
      .split('\n')
      .where((line) => line != 'Recover Storage' && line != '恢复存储')
      .join('\n');
  expect(feedback.trim(), isNotEmpty);
  final chinese = matches(RegExp(r'[\u3400-\u9fff]'));
  expect(feedback, NotificationUiCopy.isEn ? isNot(chinese) : chinese);
  for (final detail in [
    'PRIVATE',
    'StateError',
    'Preference persistence failed',
    'LocationReminderStorageIndeterminate',
  ]) {
    expect(feedback, isNot(contains(detail)));
  }
  return feedback;
}

Future<void> _openDraft(WidgetTester tester, _Fixture f) async {
  var stage = 'location-tab';
  var captured = false;
  try {
    final screen = find.byType(IntegrationsScreen);
    final tabBar = find.descendant(of: screen, matching: find.byType(TabBar));
    expect(tabBar, findsOneWidget);
    final tabs = DefaultTabController.of(tester.element(tabBar));
    final locationTab = find.descendant(
      of: tabBar,
      matching: find.text(NotificationUiCopy.tabLocation),
    );
    expect(locationTab, findsOneWidget);
    // Reveal the label through the TabBar's own horizontal scroll position;
    // do not move the body PageView as a side effect of global ensureVisible.
    final tabScroll = Scrollable.maybeOf(
      tester.element(locationTab),
      axis: Axis.horizontal,
    );
    if (tabScroll != null) {
      await tabScroll.position.ensureVisible(tester.renderObject(locationTab));
    }
    await tester.pumpAndSettle(
      const Duration(milliseconds: 50),
      EnginePhase.sendSemanticsUpdate,
      _timeout,
    );
    expect(locationTab.hitTestable(), findsOneWidget);
    await tester.tap(locationTab);
    // Fixed frame counts can leave the PageView's transition blocking hits
    // even while the selected tab and its Add button have already painted.
    await tester.pumpAndSettle(
      const Duration(milliseconds: 50),
      EnginePhase.sendSemanticsUpdate,
      _timeout,
    );
    expect(tabs.index, 1);
    expect(tabs.indexIsChanging, isFalse);

    stage = 'location-add';
    final add = find.descendant(
      of: screen,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is IconButton &&
            widget.tooltip == NotificationUiCopy.newLocationReminderTooltip,
      ),
    );
    expect(add, findsOneWidget);
    final addIcon = find.descendant(of: add, matching: find.byIcon(Icons.add));
    expect(addIcon, findsOneWidget);
    final vertical = Scrollable.maybeOf(
      tester.element(addIcon),
      axis: Axis.vertical,
    );
    // The current fixed Add button is a sibling of the location ListView. If
    // it has a vertical owner, reveal only through that owner, never PageView.
    if (vertical != null) {
      await vertical.position.ensureVisible(tester.renderObject(addIcon));
    }
    await tester.pumpAndSettle(
      const Duration(milliseconds: 50),
      EnginePhase.sendSemanticsUpdate,
      _timeout,
    );
    expect(DefaultTabController.of(tester.element(tabBar)), same(tabs));
    expect(tabs.index, 1);
    expect(addIcon.hitTestable(), findsOneWidget);
    // Tap the actual icon, rather than the tooltip's layout surrogate.
    await tester.tap(addIcon);
    stage = 'modal';
    await tester.pumpAndSettle(
      const Duration(milliseconds: 50),
      EnginePhase.sendSemanticsUpdate,
      _timeout,
    );
    await f.capture(tester, 'opened');
    captured = true;
    expect(_dialog, findsOneWidget);
    expect(_fields(), findsNWidgets(4));
  } catch (_) {
    if (!captured) await f.capture(tester, 'entry-failed-$stage');
    rethrow;
  }
}

Future<List<TextEditingValue>> _enterDraft(
  WidgetTester tester,
  List<String> text,
) async {
  for (var i = 0; i < text.length; i++) {
    final field = _fields().at(i);
    await tester.ensureVisible(field);
    await tester.enterText(field, text[i]);
  }
  final leave = find.descendant(
    of: _dialog,
    matching: find.widgetWithText(ChoiceChip, NotificationUiCopy.triggerLeave),
  );
  await tester.ensureVisible(leave);
  await tester.tap(leave);
  final fields = tester.widgetList<TextField>(_fields()).toList();
  for (final field in fields) {
    final controller = field.controller!;
    controller.selection = controller.text.length > 2
        ? TextSelection(baseOffset: 1, extentOffset: controller.text.length - 1)
        : TextSelection.collapsed(offset: controller.text.length);
  }
  await _frames(tester);
  return fields.map((field) => field.controller!.value).toList();
}

void _expectDraft(
  WidgetTester tester,
  List<TextEditingValue> values, {
  LocationTrigger trigger = LocationTrigger.leave,
}) {
  expect(
    _dialog,
    findsOneWidget,
    reason: 'draft stays editable until acknowledgement',
  );
  final fields = tester.widgetList<TextField>(_fields()).toList();
  expect(fields, hasLength(4));
  for (var i = 0; i < fields.length; i++) {
    expect(
      fields[i].controller!.text,
      values[i].text,
      reason: 'literal field $i',
    );
    expect(
      fields[i].controller!.selection,
      values[i].selection,
      reason: 'selection $i',
    );
  }
  final label = trigger == LocationTrigger.leave
      ? NotificationUiCopy.triggerLeave
      : NotificationUiCopy.triggerEnter;
  expect(
    tester
        .widget<ChoiceChip>(
          find.descendant(
            of: _dialog,
            matching: find.widgetWithText(ChoiceChip, label),
          ),
        )
        .selected,
    isTrue,
  );
}

List<String?> _fieldErrors(WidgetTester tester) => tester
    .widgetList<TextField>(_fields())
    .map((field) => field.decoration?.errorText)
    .toList();

void _expectDialogTheme(WidgetTester tester, _Fixture f) {
  final actual = Theme.of(tester.element(_dialog));
  expect(actual.colorScheme, f.theme.brand.theme.colorScheme);
  expect(actual.brightness, f.theme.brand.theme.brightness);
  final actualSurface = actual.extension<AppSurfaceStyle>();
  final expectedSurface = f.theme.brand.theme.extension<AppSurfaceStyle>();
  expect(actualSurface?.cardFillColor, expectedSurface?.cardFillColor);
  expect(actualSurface?.navBarBlurSigma, expectedSurface?.navBarBlurSigma);
  expect(
    find.text(NotificationUiCopy.newLocationReminderTitle),
    findsOneWidget,
  );
}

void _expectExplicitRetry(WidgetTester tester) {
  expect(_submitButton(tester).onPressed, isNotNull);
  final label = find.descendant(
    of: _primary(),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Text &&
          (widget.data == I18n.tr('action.retry') ||
              widget.data == I18n.tr('action.save')),
    ),
  );
  expect(label, findsOneWidget, reason: 'retry is an explicit user action');
}

String _feedback(WidgetTester tester) {
  final excluded = {
    NotificationUiCopy.newLocationReminderTitle,
    NotificationUiCopy.reminderTitleLabel,
    NotificationUiCopy.latitudeLabel,
    NotificationUiCopy.longitudeLabel,
    NotificationUiCopy.radiusMetersLabel,
    NotificationUiCopy.triggerDirectionLabel,
    NotificationUiCopy.triggerEnter,
    NotificationUiCopy.triggerLeave,
    I18n.tr('action.cancel'),
    I18n.tr('action.save'),
    I18n.tr('action.retry'),
    ..._draft,
    _literalTitle.trim(),
  };
  final text = find.byWidgetPredicate((widget) => widget is Text);
  final messages = <String>{
    ...tester
        .widgetList<Text>(find.descendant(of: _dialog, matching: text))
        .map((widget) => widget.data ?? widget.textSpan?.toPlainText() ?? ''),
    ...tester
        .widgetList<Text>(
          find.descendant(of: find.byType(SnackBar), matching: text),
        )
        .map((widget) => widget.data ?? widget.textSpan?.toPlainText() ?? ''),
    ..._fieldErrors(tester).whereType<String>(),
  }..removeWhere((value) => value.trim().isEmpty || excluded.contains(value));
  return (messages.toList()..sort()).join('\n');
}

Future<void> _expectReachableActions(WidgetTester tester) async {
  final size = tester.view.physicalSize / tester.view.devicePixelRatio;
  final keyboard = MediaQuery.viewInsetsOf(tester.element(_dialog)).bottom;
  final viewport = Rect.fromLTWH(0, 0, size.width, size.height - keyboard);
  for (final action in [
    _primary(),
    find.descendant(
      of: _dialog,
      matching: find.widgetWithText(TextButton, I18n.tr('action.cancel')),
    ),
  ]) {
    await tester.ensureVisible(action);
    await _frames(tester);
    expect(action.hitTestable(), findsOneWidget);
    final rect = tester.getRect(action);
    expect(viewport.inflate(.1).contains(rect.topLeft), isTrue);
    expect(viewport.inflate(.1).contains(rect.bottomRight), isTrue);
  }
}

Future<void> _expectCommitted(
  _Fixture f,
  Map<String, dynamic> attempted,
) async {
  final rows = await f.store.diskRows();
  expect(rows, hasLength(2));
  expect(rows.first, f.existing.toJson());
  final row = rows.singleWhere((r) => r['id'] == attempted['id']);
  expect(row, attempted);
  expect(row['title'], _literalTitle.trim());
  expect(row['latitude'], 39.9042);
  expect(row['longitude'], 116.4074);
  expect(row['radiusMeters'], 250);
  expect(row['trigger'], 'leave');
  expect(f.locations.reminders.map((r) => r.toJson()), rows);
  expect(f.persisted, 1);
  await f.prefs.reload();
  expect(jsonDecode(f.prefs.getString(_key)!) as List, rows);
}

Future<_Fixture> _mount(
  WidgetTester tester,
  String brand,
  String caseName,
) async {
  final previousStore = SharedPreferencesStorePlatform.instance;
  final previousLocale = I18n.current;
  AccountLocalDataCleaner.invalidateInFlightAccountWrites();
  SharedPreferences.setMockInitialValues({});
  // Confirm retirement against the empty mock platform before installing the
  // fixture's previously acknowledged reminder and theme preferences.
  await tester.runAsync(
    () => AccountLocalDataCleaner.clearSharedPreferences().timeout(_timeout),
  );
  // getInstance cached the empty cleanup platform; let the seeded store supply
  // the next instance instead of reusing that empty cache.
  SharedPreferences.setMockInitialValues({});
  final f = (await tester.runAsync(() async => _Fixture(brand, caseName)))!;
  SharedPreferencesStorePlatform.instance = f.store;
  I18n.setLocale(AppLocale.zh);
  addTearDown(() => f.close(tester, previousStore, previousLocale));
  await tester.runAsync(() async {
    f.prefs = await SharedPreferences.getInstance();
    await f.theme.loadFromStorage().timeout(_timeout);
    await f.locale.loadFromStorage().timeout(_timeout);
    await f.locations.loadFromStorage().timeout(_timeout);
    expect(f.prefs.getString(_key), f.originalRaw);
    expect(f.locations.reminders.map((r) => r.id), ['existing']);
    if (_evidenceRoot?.isNotEmpty ?? false) {
      await loadWeeklyReviewScreenshotFonts().timeout(_timeout);
    }
  });
  expect(f.theme.brand.id, brand);
  tester.view.physicalSize = _View.normal.size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    ValueListenableBuilder<LocationReminderProvider>(
      valueListenable: f.current,
      builder: (context, locations, _) => MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>.value(value: f.theme),
          ChangeNotifierProvider<LocaleProvider>.value(value: f.locale),
          ChangeNotifierProvider<CalendarSyncProvider>.value(value: f.calendar),
          ChangeNotifierProvider<LocationReminderProvider>.value(
            value: locations,
          ),
          ChangeNotifierProvider<NotificationService>.value(
            value: f.notifications,
          ),
        ],
        child: Consumer<ThemeProvider>(
          builder: (context, theme, _) => ValueListenableBuilder<AppLocale>(
            valueListenable: I18n.localeListenable,
            builder: (context, locale, _) => MaterialApp(
              navigatorKey: f.navigator,
              theme: theme.brand.theme,
              locale: locale.flutterLocale,
              supportedLocales: const [Locale('zh'), Locale('en')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              builder: (context, child) => ValueListenableBuilder<_View>(
                valueListenable: f.view,
                builder: (context, view, _) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    size: view.size,
                    textScaler: TextScaler.linear(view.scale),
                    viewInsets: EdgeInsets.only(bottom: view.keyboard),
                  ),
                  child: RepaintBoundary(key: f.captureKey, child: child!),
                ),
              ),
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    key: _open,
                    onPressed: () {
                      f.parentRoute = MaterialPageRoute<void>(
                        builder: (_) => const BrandRouteSurface(
                          child: IntegrationsScreen(),
                        ),
                      );
                      unawaited(
                        Navigator.of(context).push<void>(f.parentRoute),
                      );
                    },
                    child: const Text('Open synthetic extensions'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(_open));
  // Settle the pushed route before attempting a tab transition on its body.
  await tester.pumpAndSettle(
    const Duration(milliseconds: 50),
    EnginePhase.sendSemanticsUpdate,
    _timeout,
  );
  final screen = find.byType(IntegrationsScreen);
  if (screen.evaluate().length != 1 || !f.parentRoute.isCurrent) {
    await f.capture(tester, 'entry-failed-route');
  }
  expect(screen, findsOneWidget);
  expect(f.parentRoute.isCurrent, isTrue);
  expect(f.store.draftAttempts, isEmpty);
  expect(tester.takeException(), isNull);
  return f;
}

class _Fixture {
  _Fixture(this.initialBrand, this.caseName) {
    originalRaw = '[\n  ${jsonEncode(existing.toJson())}\n]\n';
    store = _Store(initialBrand, originalRaw);
    current = ValueNotifier(locations);
    providers.add(locations);
    locations.onLocalMutationPersisted = () => persisted++;
  }

  final String initialBrand;
  final String caseName;
  final theme = ThemeProvider();
  final locale = LocaleProvider();
  final calendar = CalendarSyncProvider();
  final notifications = NotificationService();
  final locations = LocationReminderProvider();
  final providers = <LocationReminderProvider>[];
  final navigator = GlobalKey<NavigatorState>();
  final captureKey = GlobalKey();
  final view = ValueNotifier(_View.normal);
  final existing = LocationReminder(
    id: 'existing',
    title: 'Previously acknowledged / 已保存',
    latitude: 10,
    longitude: 20,
    radiusMeters: 300,
    createdAt: DateTime.utc(2026, 11, 8, 12),
    updatedAt: DateTime.utc(2026, 11, 8, 12),
  );
  late final _Store store;
  late final String originalRaw;
  late final ValueNotifier<LocationReminderProvider> current;
  late final SharedPreferences prefs;
  late MaterialPageRoute<void> parentRoute;
  int persisted = 0;
  int captureIndex = 0;

  void setView(WidgetTester tester, _View next) {
    tester.view.physicalSize = next.size;
    view.value = next;
  }

  Future<void> switchPresentation(WidgetTester tester) async {
    await tester.runAsync(() async {
      await locale.setLocale(AppLocale.en).timeout(_timeout);
      expect(
        await theme
            .setBrand(
              initialBrand == 'defaultBrand' ? 'liquidGlass' : 'defaultBrand',
            )
            .timeout(_timeout),
        isTrue,
      );
      // A global drain here would await the intentionally held location write.
    });
    await _frames(tester);
  }

  Future<void> invalidate(
    WidgetTester tester,
    _Invalidation invalidation,
  ) async {
    switch (invalidation) {
      case _Invalidation.parent:
        navigator.currentState!.removeRoute(parentRoute);
      case _Invalidation.account:
        AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      case _Invalidation.replacement:
        final next = (await tester.runAsync(
          () async => LocationReminderProvider(),
        ))!;
        providers.add(next);
        current.value = next;
      case _Invalidation.storageReset:
        final before = locations.storageGeneration;
        locations.resetLocalState();
        expect(locations.storageGeneration, before + 1);
    }
    await _frames(tester);
  }

  Future<void> drain(WidgetTester tester) async {
    await _frames(tester);
    await tester.runAsync(
      () => AccountPreferenceWrites.drain().timeout(_timeout),
    );
    await _frames(tester);
  }

  Future<void> capture(WidgetTester tester, String phase) async {
    // State assertions need the same rebuilt frame with or without PNG output.
    await tester.pump();
    final root = _evidenceRoot;
    if (root == null || root.isEmpty) return;
    final boundary =
        captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final actualFields = tester
        .widgetList<TextField>(_fields())
        .map(
          (field) => {
            'text': field.controller?.text,
            'selectionBase': field.controller?.selection.baseOffset,
            'selectionExtent': field.controller?.selection.extentOffset,
            'error': field.decoration?.errorText,
          },
        )
        .toList();
    final fileName = '$initialBrand-$caseName-${captureIndex++}-$phase';
    await tester.runAsync(() async {
      final evidence = Directory(
        'evidence',
      ).absolute.uri.normalizePath().toFilePath();
      final supplied = Directory(
        root,
      ).absolute.uri.normalizePath().toFilePath();
      final prefix = evidence.endsWith(Platform.pathSeparator)
          ? evidence
          : '$evidence${Platform.pathSeparator}';
      if (supplied != evidence && !supplied.startsWith(prefix)) {
        throw StateError(
          'DUOYI_THEME_DIALOG_EVIDENCE_DIR must be under evidence/',
        );
      }
      final batch = Directory('$supplied/$_runName');
      await batch.create(recursive: true);
      final picture = await boundary.toImage(pixelRatio: 1);
      try {
        final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
        final png = bytes!;
        await File('${batch.path}/$fileName.png').writeAsBytes(
          png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
        );
        await File('${batch.path}/$fileName.json').writeAsString(
          const JsonEncoder.withIndent('  ').convert({
            'case': caseName,
            'phase': phase,
            'initialBrand': initialBrand,
            'actualBrand': theme.brand.id,
            'locale': I18n.current.name,
            'physicalSize': [
              tester.view.physicalSize.width,
              tester.view.physicalSize.height,
            ],
            'mediaSize': [view.value.size.width, view.value.size.height],
            'textScale': view.value.scale,
            'keyboardInset': view.value.keyboard,
            'modalPresent': actualFields.isNotEmpty,
            'literalFields': actualFields,
            'expectedValidDraft': _draft,
            'draftWriteAttempts': store.draftAttempts,
            'diskRaw': await store.diskRaw(),
            'memoryRows': locations.reminders.map((r) => r.toJson()).toList(),
            'persistedCallbacks': persisted,
            'storageNeedsReconciliation': locations.storageNeedsReconciliation,
          }),
        );
      } finally {
        picture.dispose();
      }
    });
  }

  Future<void> close(
    WidgetTester tester,
    SharedPreferencesStorePlatform previousStore,
    AppLocale previousLocale,
  ) async {
    try {
      // Release this fixture's writes even if a baseline assertion failed early.
      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      await tester.pumpWidget(const SizedBox.shrink());
      store.releaseAll();
      await drain(tester);
    } finally {
      for (final provider in providers) {
        provider.dispose();
      }
      current.dispose();
      view.dispose();
      theme.dispose();
      locale.dispose();
      calendar.dispose();
      notifications.dispose();
      tester.view.reset();
      I18n.setLocale(previousLocale);
      SharedPreferences.resetStatic();
      SharedPreferencesStorePlatform.instance = previousStore;
    }
  }
}

class _HeldWrite {
  _HeldWrite(this.failure);
  final _Failure? failure;
  final started = Completer<void>();
  final _released = Completer<void>();
  void release() {
    if (!_released.isCompleted) _released.complete();
  }
}

class _Store extends InMemorySharedPreferencesStore {
  _Store(String brand, String originalRaw)
    : super.withData({
        'flutter.duoyi_locale_v1': 'zh',
        'flutter.active_brand': brand,
        'flutter.theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
        _platformKey: originalRaw,
      });

  final failures = <_Failure>[];
  final snapshots = <List<Map<String, dynamic>>>[];
  final _queuedHolds = <_HeldWrite>[];
  final _allHolds = <_HeldWrite>[];
  List<Map<String, dynamic>> get draftAttempts => snapshots
      .expand((rows) => rows)
      .where((row) => row['title'] == _literalTitle.trim())
      .toList();

  _HeldWrite holdNext({_Failure? failure}) {
    final held = _HeldWrite(failure);
    _queuedHolds.add(held);
    _allHolds.add(held);
    return held;
  }

  void releaseAll() {
    for (final held in _allHolds) {
      held.release();
    }
  }

  Future<String?> diskRaw() async => (await getAll())[_platformKey] as String?;
  Future<List<Map<String, dynamic>>> diskRows() async =>
      _decodeRows(await diskRaw());

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key != _platformKey) return super.setValue(type, key, value);
    snapshots.add(_decodeRows(value as String));
    final held = _queuedHolds.isEmpty ? null : _queuedHolds.removeAt(0);
    final failure =
        held?.failure ?? (failures.isEmpty ? null : failures.removeAt(0));
    if (held != null) {
      held.started.complete();
      await held._released.future;
    }
    if (failure == _Failure.returnsFalse) return false;
    if (failure == _Failure.throwsBeforeWrite) {
      throw StateError(
        'PRIVATE synthetic location write failure before disk change',
      );
    }
    await super.setValue(type, key, value);
    if (failure == _Failure.writeThenFalse) return false;
    if (failure == _Failure.writeThenThrow) {
      throw StateError(
        'PRIVATE synthetic location write failure after disk change',
      );
    }
    return true;
  }
}

List<Map<String, dynamic>> _decodeRows(String? raw) =>
    (jsonDecode(raw ?? '[]') as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
