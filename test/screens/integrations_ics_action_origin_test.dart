// ignore_for_file: depend_on_referenced_packages

// Real-provider action-origin regressions. Main owns source changes, formatting,
// execution and captures. These cases intentionally retain menus and operations
// across source/route changes; they do not accept current stale-action behavior.
import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/ics_subscription_storage.dart';
import 'package:duoyi/core/notification_ui_copy.dart';
import 'package:duoyi/providers/location_reminder_provider.dart';
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/integrations_screen.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/calendar_sync_service.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/ics_visual_capture.dart';
import '../support/weekly_review_screenshot_font.dart';

const _key = 'duoyi_ics_subscriptions_v1';
const _cacheKey = 'duoyi_ics_events_existing';
const _timeout = Duration(seconds: 5);
const _open = ValueKey('open-ics-action-origin-fixture');
const _name = 'Literal 用户订阅';
const _recreatedName = 'Recreated 用户订阅';
const _draftName = '  Retained 用户 draft  ';
const _draftUrl = '  https://feed.test/draft.ics  ';
const _newTitle = 'Late fetched 用户事件';
const _emptyCalendar = 'BEGIN:VCALENDAR\nVERSION:2.0\nEND:VCALENDAR\n';
const _calendar = '''
BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:late@test
SUMMARY:Late fetched 用户事件
DTSTART:20261109T110000
DTEND:20261109T120000
END:VEVENT
END:VCALENDAR
''';
final _dialog = find.byType(AppDialog);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final action in [_MenuAction.pause, _MenuAction.delete]) {
      testWidgets(
        '$brand retained ${action.name} menu rejects reset and same-ID recreation',
        (
          tester,
        ) => _withFixture(tester, brand, 'retained-${action.name}-recreation', (
          f,
        ) async {
          await _openMenu(tester, _name);
          await f.capturePhase(tester, 'original-menu-open');
          final retained = _menuItem(_menuLabel(action));
          expect(retained, findsOneWidget);
          final replay = _retainMenuAction(tester, _name, retained);
          final generation = f.calendar.icsLifetimeGeneration;
          // Avoid a frame between reset/removal/recreation: the same keyed row
          // can survive reconciliation while its already-open menu remains old.
          await tester.runAsync(() async {
            f.calendar.resetLocalState();
            await f.calendar.removeSubscription('existing').timeout(_timeout);
            await f.calendar
                .addSubscription(
                  const IcsSubscription(
                    id: 'existing',
                    name: _recreatedName,
                    url: 'https://feed.test/recreated.ics',
                  ),
                )
                .timeout(_timeout);
          });
          await _frames(tester);
          await f.capturePhase(tester, 'recreated-source-retained-menu');
          expect(f.calendar.icsLifetimeGeneration, greaterThan(generation));
          final raw = await f.snapshot();
          final rows = _rows(f.calendar);
          f.store.writes.clear();

          replay();
          await f.drain(tester);
          await _until(
            tester,
            () => _menuItems().evaluate().isEmpty,
            'retained menu dismissed',
          );
          await f.capturePhase(tester, 'retained-action-completed');

          await f.expectRaw(raw);
          expect(_rows(f.calendar), rows);
          expect(f.calendar.subscriptions.single.name, _recreatedName);
          expect(f.calendar.subscriptions.single.enabled, isTrue);
          expect(
            f.store.writes,
            isEmpty,
            reason:
                'an old menu has no write authority over the recreated source',
          );
          expect(f.feed.requests, isEmpty);
          expect(find.byType(SnackBar), findsNothing);
          expect(f.parentRoute.isCurrent, isTrue);
          expect(find.byType(IntegrationsScreen), findsOneWidget);
          expect(tester.takeException(), isNull);

          // A fresh opening owns a different action record. The original
          // callback must not adopt or consume it when replayed a second time.
          f.store.writes.clear();
          await _openMenu(tester, _recreatedName);
          await f.capturePhase(tester, 'fresh-recreated-menu-open');
          final freshItem = _menuItem(_menuLabel(action));
          final freshRoute = ModalRoute.of(tester.element(freshItem))!;
          replay();
          await f.drain(tester);
          await f.capturePhase(
            tester,
            'old-callback-replayed-with-recreated-menu',
          );
          await f.expectRaw(raw);
          expect(_rows(f.calendar), rows);
          expect(
            f.store.writes,
            isEmpty,
            reason:
                'the old callback cannot write through the new opening record',
          );
          expect(f.feed.requests, isEmpty);
          expect(find.byType(SnackBar), findsNothing);
          expect(
            freshRoute.isCurrent,
            isTrue,
            reason: 'the old callback cannot dismiss the current menu',
          );
          expect(freshItem, findsOneWidget);
          expect(ModalRoute.of(tester.element(freshItem)), same(freshRoute));
          expect(tester.takeException(), isNull);

          // Only the actual current selection may now cross the write boundary.
          f.store.writes.clear();
          await tester.tap(freshItem);
          await f.drain(tester);
          await _until(
            tester,
            () => _menuItems().evaluate().isEmpty,
            'fresh recreated menu dismissed',
          );
          await f.capturePhase(tester, 'fresh-recreated-action-completed');
          await f.prefs.reload();
          expect(f.store.writes, contains(_key));
          if (action == _MenuAction.pause) {
            final expected = [
              Map<String, dynamic>.from(rows.single)..['enabled'] = false,
            ];
            expect(_rows(f.calendar), expected);
            expect(_decodeRows(f.prefs.getString(_key)), expected);
            expect(await f.store.raw(_cacheKey), raw[_cacheKey]);
          } else {
            expect(f.calendar.subscriptions, isEmpty);
            expect(_decodeRows(f.prefs.getString(_key)), isEmpty);
            expect(await f.store.raw(_cacheKey), isNull);
          }
          expect(f.calendar.allEvents(), isEmpty);
          expect(f.feed.requests, isEmpty);
          expect(f.parentRoute.isCurrent, isTrue);
          expect(tester.takeException(), isNull);
        }),
      );
    }

    testWidgets(
      '$brand retained Pause keeps its original intent after a peer pauses the source',
      (tester) => _withFixture(tester, brand, 'retained-pause-peer-paused', (
        f,
      ) async {
        final peer = await f.peer(tester);
        await _openMenu(tester, _name);
        await f.capturePhase(tester, 'original-pause-menu-open');
        final retainedPause = _menuItem(_menuLabel(_MenuAction.pause));
        final replay = _retainMenuAction(tester, _name, retainedPause);
        await tester.runAsync(() async {
          await peer
              .updateSubscription(
                peer.subscriptions.single.copyWith(enabled: false),
              )
              .timeout(_timeout);
          // The visible row now knows it is paused, but its popup still says Pause.
          await f.calendar.loadFromStorage().timeout(_timeout);
        });
        await _frames(tester);
        await f.capturePhase(tester, 'peer-paused-retained-menu');
        expect(f.calendar.subscriptions.single.enabled, isFalse);
        final raw = await f.snapshot();
        final pausedRows = _rows(f.calendar);
        f.store.writes.clear();

        replay();
        await f.drain(tester);
        await _until(
          tester,
          () => _menuItems().evaluate().isEmpty,
          'old Pause menu dismissed',
        );
        await f.capturePhase(tester, 'retained-pause-completed');

        await f.expectRaw(raw);
        expect(_rows(f.calendar), pausedRows);
        expect(
          f.calendar.subscriptions.single.enabled,
          isFalse,
          reason:
              'selecting a previously rendered Pause must never resume a now-paused row',
        );
        expect(f.calendar.allEvents(), isEmpty);
        expect(f.store.writes, isEmpty);
        expect(f.feed.requests, isEmpty);
        expect(find.byType(SnackBar), findsNothing);
        expect(f.parentRoute.isCurrent, isTrue);
        expect(find.byType(IntegrationsScreen), findsOneWidget);
        expect(tester.takeException(), isNull);

        // The old Pause callback must not adopt or consume a newly opened
        // Resume record. Resume remains selectable from that same opening.
        f.store.writes.clear();
        await _openMenu(tester, _name);
        await f.capturePhase(tester, 'fresh-resume-menu-open');
        final freshResume = _menuItem(
          NotificationUiCopy.isEn ? 'Resume' : '启用',
        );
        final freshRoute = ModalRoute.of(tester.element(freshResume))!;
        replay();
        await f.drain(tester);
        await f.capturePhase(tester, 'old-pause-replayed-with-resume-menu');
        await f.expectRaw(raw);
        expect(_rows(f.calendar), pausedRows);
        expect(f.calendar.allEvents(), isEmpty);
        expect(
          f.store.writes,
          isEmpty,
          reason: 'the original Pause cannot acquire the fresh Resume record',
        );
        expect(f.feed.requests, isEmpty);
        expect(find.byType(SnackBar), findsNothing);
        expect(
          freshRoute.isCurrent,
          isTrue,
          reason: 'the old Pause cannot dismiss the current Resume menu',
        );
        expect(freshResume, findsOneWidget);
        expect(ModalRoute.of(tester.element(freshResume)), same(freshRoute));
        expect(tester.takeException(), isNull);

        // These writes belong exclusively to the new owned Resume selection.
        f.store.writes.clear();
        await tester.tap(freshResume);
        await f.drain(tester);
        await _until(
          tester,
          () => _menuItems().evaluate().isEmpty,
          'fresh Resume menu dismissed',
        );
        await f.capturePhase(tester, 'fresh-resume-completed');
        await f.prefs.reload();
        final resumedRows = [
          Map<String, dynamic>.from(pausedRows.single)..['enabled'] = true,
        ];
        expect(f.store.writes, contains(_key));
        expect(_rows(f.calendar), resumedRows);
        expect(_decodeRows(f.prefs.getString(_key)), resumedRows);
        expect(await f.store.raw(_cacheKey), raw[_cacheKey]);
        expect(f.calendar.allEvents().map((event) => event.title).toList(), [
          'Confirmed 用户事件',
        ]);
        expect(f.feed.requests, isEmpty);
        expect(f.parentRoute.isCurrent, isTrue);
        expect(tester.takeException(), isNull);
      }),
    );

    for (final action in [_MenuAction.pause, _MenuAction.delete]) {
      testWidgets(
        '$brand ${action.name} durable failure restores confirmed data and displays live safe feedback',
        (
          tester,
        ) => _withFixture(tester, brand, '${action.name}-durable-failure', (
          f,
        ) async {
          final before = await f.snapshot();
          final rows = _rows(f.calendar);
          final events = f.calendar
              .allEvents()
              .map((event) => event.title)
              .toList();
          final held = f.store.holdNext(
            action == _MenuAction.pause ? _key : _cacheKey,
            fault: action == _MenuAction.pause
                ? _Fault.writeThenFalse
                : _Fault.writeThenThrow,
          );
          await _openMenu(tester, _name);
          final feedbackBefore = _feedbackBaseline(tester);
          await f.capturePhase(tester, 'mutation-menu-open');
          await tester.tap(_menuItem(_menuLabel(action)));
          await _until(
            tester,
            () => held.started.isCompleted,
            'owned mutation ACK held',
          );
          await f.capturePhase(tester, 'mutation-ack-held');
          feedbackBefore.addAll(_feedbackBaseline(tester));
          expect(_rows(f.calendar), rows);
          expect(
            f.calendar.allEvents().map((event) => event.title).toList(),
            events,
          );
          held.release();
          await f.drain(tester);
          await _until(
            tester,
            () => _menuItems().evaluate().isEmpty,
            'failed action menu dismissed',
          );
          await f.capturePhase(tester, 'mutation-failed-zh');

          await f.expectRaw(before);
          expect(_rows(f.calendar), rows);
          expect(
            f.calendar.allEvents().map((event) => event.title).toList(),
            events,
          );
          final receiptZh = _actionFailureFeedback(
            tester,
            action,
            feedbackBefore,
          );
          expect(receiptZh.copy, matches(RegExp(r'[\u3400-\u9fff]')));
          _expectLiteralSourceLabels();
          final writesAfterFailure = f.store.writes.length;
          await f.switchPresentation(tester);
          await f.capturePhase(tester, 'mutation-failed-en');
          final receiptEn = _actionFailureFeedback(
            tester,
            action,
            feedbackBefore,
            retainedOwner: receiptZh.owner,
          );
          expect(receiptEn.copy, isNot(receiptZh.copy));
          expect(receiptEn.copy, isNot(matches(RegExp(r'[\u3400-\u9fff]'))));
          _expectLiteralSourceLabels();
          expect(_rows(f.calendar), rows);
          await f.expectRaw(before);
          expect(
            f.store.writes,
            hasLength(writesAfterFailure),
            reason: 'presentation changes do not replay the mutation',
          );
          expect(f.feed.requests, isEmpty);

          // Retry through a fresh, currently owned menu, without prescribing a
          // new failure-message sentence or the feedback host's Retry placement.
          await _openMenu(tester, _name);
          await tester.tap(_menuItem(_menuLabel(action)));
          await f.drain(tester);
          await _until(
            tester,
            () => _menuItems().evaluate().isEmpty,
            'explicit retry menu dismissed',
          );
          await f.capturePhase(tester, 'mutation-retry-completed');
          await f.prefs.reload();
          if (action == _MenuAction.pause) {
            expect(f.calendar.subscriptions.single.enabled, isFalse);
            expect(
              _decodeRows(f.prefs.getString(_key)).single['enabled'],
              isFalse,
            );
            expect(f.calendar.allEvents(), isEmpty);
            expect(await f.store.raw(_cacheKey), before[_cacheKey]);
          } else {
            expect(f.calendar.subscriptions, isEmpty);
            expect(f.calendar.allEvents(), isEmpty);
            expect(_decodeRows(f.prefs.getString(_key)), isEmpty);
            expect(await f.store.raw(_cacheKey), isNull);
          }
          expect(f.feed.requests, isEmpty);
          expect(tester.takeException(), isNull);
        }),
      );
    }

    testWidgets(
      '$brand rejected Pause feedback and retained retry cannot adopt a same-revision replacement provider',
      (
        tester,
      ) => _withFixture(tester, brand, 'pause-failure-provider-replacement', (
        f,
      ) async {
        final before = await f.snapshot();
        final rows = _rows(f.calendar);
        final events = f.calendar
            .allEvents()
            .map((event) => event.title)
            .toList();
        final held = f.store.holdNext(_key, fault: _Fault.writeThenFalse);
        await _openMenu(tester, _name);
        final feedbackBefore = _feedbackBaseline(tester);
        await tester.tap(_menuItem(_menuLabel(_MenuAction.pause)));
        await _until(
          tester,
          () => held.started.isCompleted,
          'Pause rejection ACK held',
        );
        feedbackBefore.addAll(_feedbackBaseline(tester));
        held.release();
        await f.drain(tester);
        await _until(
          tester,
          () => _menuItems().evaluate().isEmpty,
          'rejected Pause menu dismissed',
        );
        await f.capturePhase(tester, 'pause-failure-original-provider');
        await f.expectRaw(before);
        expect(_rows(f.calendar), rows);
        expect(
          f.calendar.allEvents().map((event) => event.title).toList(),
          events,
        );
        _actionFailureFeedback(tester, _MenuAction.pause, feedbackBefore);
        final retryControl = _pauseFailureRetry();
        expect(retryControl, findsOneWidget);
        final oldRetry = tester.widget<IconButton>(retryControl).onPressed;
        expect(
          oldRetry,
          isNotNull,
          reason: 'the owned rejected Pause has an actionable retry',
        );
        final failedLifetime = f.calendar.icsLifetimeGeneration;
        final failedSourceRevision = IcsSubscriptionStorage.sourceRevision(
          'existing',
        );

        // Leave the failed provider alive, and hold ID/lifetime/source revision
        // equal. Only provider identity distinguishes the new source owner.
        final replacement = await f.peer(tester);
        expect(replacement, isNot(same(f.calendar)));
        expect(replacement.icsLifetimeGeneration, failedLifetime);
        expect(_rows(replacement), rows);
        expect(
          IcsSubscriptionStorage.sourceRevision('existing'),
          failedSourceRevision,
        );
        f.store.writes.clear();
        f.current.value = replacement;
        await _frames(tester);
        await f.capturePhase(tester, 'pause-failure-provider-replaced');
        final adoptedError = _ownedActionFailureReceipts(
          tester,
          _MenuAction.pause,
          const <String>{},
        ).isNotEmpty;
        final adoptedRetry = _pauseFailureRetry().evaluate().isNotEmpty;

        // Invoke the original callable even if replacement removes its control.
        // Record presentation first so invoking it cannot hide an adopted error.
        oldRetry!();
        await f.drain(tester);
        await f.capturePhase(tester, 'old-pause-retry-callback-completed');
        await f.expectRaw(before);
        expect(f.current.value, same(replacement));
        expect(_rows(f.calendar), rows);
        expect(_rows(replacement), rows);
        expect(
          f.calendar.allEvents().map((event) => event.title).toList(),
          events,
        );
        expect(
          replacement.allEvents().map((event) => event.title).toList(),
          events,
        );
        expect(f.calendar.icsLifetimeGeneration, failedLifetime);
        expect(replacement.icsLifetimeGeneration, failedLifetime);
        expect(
          IcsSubscriptionStorage.sourceRevision('existing'),
          failedSourceRevision,
        );
        expect(
          f.store.writes,
          isEmpty,
          reason:
              'a retained failed-action retry has no authority through either provider after replacement',
        );
        expect(f.feed.requests, isEmpty);
        expect(f.calendar.icsRefreshResults, isEmpty);
        expect(replacement.icsRefreshResults, isEmpty);
        expect(
          adoptedError,
          isFalse,
          reason:
              'the old failure must disappear when its provider is replaced',
        );
        expect(
          adoptedRetry,
          isFalse,
          reason:
              'the replacement must not inherit the old failed-action retry',
        );
        expect(
          _ownedActionFailureReceipts(
            tester,
            _MenuAction.pause,
            const <String>{},
          ),
          isEmpty,
        );
        expect(_pauseFailureRetry(), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
        expect(f.parentRoute.isCurrent, isTrue);
        expect(find.byType(IntegrationsScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      }),
    );

    testWidgets(
      '$brand old failed retry cannot clear a newer failed action',
      (tester) => _withFixture(tester, brand, 'newer-error-retained-retry', (
        f,
      ) async {
        final oldRetry = await _rejectPauseAndRetainRetry(tester, f);
        final oldRevision = IcsSubscriptionStorage.sourceRevision('existing');
        // Only an accepted source edit advances the ICS revision. Establish
        // that real boundary before creating the newer failed-action receipt.
        await tester.runAsync(
          () => f.calendar.updateSubscription(
            f.calendar.subscriptions.single.copyWith(
              colorValue: f.calendar.subscriptions.single.colorValue ^ 1,
            ),
          ),
        );
        await f.drain(tester);
        final before = await f.snapshot();
        final freshRetry = await _rejectPauseAndRetainRetry(tester, f);
        expect(
          IcsSubscriptionStorage.sourceRevision('existing'),
          greaterThan(oldRevision),
        );
        final writes = f.store.writes.toList();
        await _invokeRetainedRetry(tester, oldRetry);
        await f.drain(tester);
        expect(f.store.writes, writes);
        expect(f.feed.requests, isEmpty);
        expect(_pauseFailureRetry(), findsOneWidget);
        expect(
          tester.widget<IconButton>(_pauseFailureRetry()).onPressed,
          same(freshRetry),
        );
        _actionFailureFeedback(tester, _MenuAction.pause, const <String>{});
        await f.expectRaw(before);
        await f.capturePhase(tester, 'newer-error-retained');
        await tester.tap(_pauseFailureRetry());
        await f.drain(tester);
        await f.prefs.reload();
        expect(f.calendar.subscriptions.single.enabled, isFalse);
        expect(_decodeRows(f.prefs.getString(_key)).single['enabled'], isFalse);
        expect(_pauseFailureRetry(), findsNothing);
        await f.capturePhase(tester, 'newer-error-fresh-retry-completed');
        expect(tester.takeException(), isNull);
      }),
    );

    testWidgets(
      '$brand retained failed retry is harmless after tile disposal',
      (tester) => _withFixture(tester, brand, 'disposed-error-retained-retry', (
        f,
      ) async {
        final oldRetry = await _rejectPauseAndRetainRetry(tester, f);
        await _openMenu(tester, _name);
        await tester.tap(_menuItem(_menuLabel(_MenuAction.delete)));
        await f.drain(tester);
        await _until(
          tester,
          () => _menuItems().evaluate().isEmpty,
          'delete menu dismissed',
        );
        expect(f.calendar.subscriptions, isEmpty);
        expect(_card().evaluate(), isEmpty);
        final before = await f.snapshot();
        final writes = f.store.writes.toList();
        await _invokeRetainedRetry(tester, oldRetry);
        await f.drain(tester);
        expect(f.store.writes, writes);
        expect(f.feed.requests, isEmpty);
        await f.expectRaw(before);
        expect(tester.takeException(), isNull);
      }),
    );

    for (final revoke in [
      _RefreshRevocation.cover,
      _RefreshRevocation.replacement,
    ]) {
      testWidgets(
        '$brand global refresh rejects ${revoke.name} origin during held HTTP and releases its action',
        (tester) => _withFixture(
          tester,
          brand,
          'global-refresh-${revoke.name}',
          (f) async {
            final before = await f.snapshot();
            final rows = _rows(f.calendar);
            final old = f.feed.holdNext();
            await tester.tap(_globalRefresh());
            await _until(
              tester,
              () => old.started.isCompleted,
              'outgoing global HTTP held',
            );
            await f.capturePhase(tester, 'global-http-held');
            MaterialPageRoute<void>? cover;
            if (revoke == _RefreshRevocation.cover) {
              cover = await f.cover(tester);
            } else {
              final replacement = await f.peer(tester);
              expect(
                replacement.icsLifetimeGeneration,
                f.calendar.icsLifetimeGeneration,
              );
              f.current.value = replacement;
              await _frames(tester);
            }
            await f.capturePhase(tester, 'global-origin-${revoke.name}-held');
            old.release(_response(body: _calendar));
            await _until(
              tester,
              () => !f.calendar.isSyncing,
              'outgoing global run finished',
            );
            await f.drain(tester);
            await f.capturePhase(tester, 'global-revoked-completed');

            await f.expectRaw(before);
            expect(_rows(f.calendar), rows);
            expect(
              f.calendar.allEvents().map((event) => event.title),
              isNot(contains(_newTitle)),
            );
            expect(
              f.calendar.icsRefreshResults,
              isEmpty,
              reason: 'revoked UI work must not publish a per-row outcome',
            );
            expect(f.current.value.icsRefreshResults, isEmpty);
            expect(f.feed.requests, [Uri.parse(f.existing.url)]);
            expect(find.byType(SnackBar), findsNothing);
            if (cover != null) {
              expect(cover.isCurrent, isTrue);
              await f.uncover(tester, cover);
            }
            await f.capturePhase(tester, 'global-action-restored');
            expect(_button(tester, _globalRefresh()).onPressed, isNotNull);

            final fresh = f.feed.holdNext();
            await tester.tap(_globalRefresh());
            await _until(
              tester,
              () => fresh.started.isCompleted,
              'new owned global refresh dispatched',
            );
            await f.capturePhase(tester, 'fresh-global-http-held');
            fresh.release(_response());
            await f.waitResult(tester, 'existing');
            await f.capturePhase(tester, 'fresh-global-completed');
            expect(f.feed.requests, [
              Uri.parse(f.existing.url),
              Uri.parse(f.existing.url),
            ]);
            expect(
              f.current.value.icsRefreshResults['existing']!.eventCount,
              0,
            );
            expect(tester.takeException(), isNull);
          },
        ),
      );
    }

    testWidgets(
      '$brand temporary cover cancels held modal save and uncover restores a stable retry',
      (tester) => _withFixture(tester, brand, 'modal-save-cover-uncover', (
        f,
      ) async {
        await tester.tap(find.byTooltip(NotificationUiCopy.addIcsTooltip));
        await tester.pumpAndSettle(
          const Duration(milliseconds: 50),
          EnginePhase.sendSemanticsUpdate,
          _timeout,
        );
        final values = await _enterDraft(tester);
        final route = ModalRoute.of(tester.element(_dialog))!;
        f.modalRoute = route;
        await f.capturePhase(tester, 'modal-draft');
        final first = f.store.holdNext(_key);
        _button(tester, _primary()).onPressed!();
        await _until(
          tester,
          () => first.started.isCompleted,
          'modal save ACK held',
        );
        await f.capturePhase(tester, 'modal-save-ack-held');
        final issued = Map<String, dynamic>.from(f.store.draftAttempts.single);
        final cover = await f.cover(tester);
        await f.capturePhase(tester, 'modal-save-covered-held');
        first.release();
        await f.drain(tester);
        await f.capturePhase(tester, 'modal-save-canceled-covered');
        expect(cover.isCurrent, isTrue);
        await f.expectBaseline();
        expect(f.feed.requests, isEmpty);
        expect(find.byType(SnackBar), findsNothing);
        await f.uncover(tester, cover);
        await f.capturePhase(tester, 'modal-save-uncovered');

        expect(route.isCurrent, isTrue);
        expect(ModalRoute.of(tester.element(_dialog)), same(route));
        expect(_fieldValues(tester), values);
        expect(
          _button(tester, _primary()).onPressed,
          isNotNull,
          reason:
              'a canceled covered save cannot leave the retained form permanently busy',
        );
        expect(
          find.descendant(
            of: _dialog,
            matching: find.byType(CircularProgressIndicator),
          ),
          findsNothing,
        );
        expect(f.store.draftAttempts, hasLength(1));
        final retry = f.store.holdNext(_key);
        final refresh = f.feed.holdNext();
        _button(tester, _primary()).onPressed!();
        await _until(
          tester,
          () => retry.started.isCompleted,
          'uncovered explicit retry held',
        );
        await f.capturePhase(tester, 'modal-retry-ack-held');
        expect(f.store.draftAttempts, hasLength(2));
        expect(f.store.draftAttempts.last, issued);
        expect(f.feed.requests, isEmpty);
        retry.release();
        await f.drain(tester);
        await _until(
          tester,
          () => refresh.started.isCompleted,
          'retry followup HTTP dispatched',
        );
        await f.capturePhase(tester, 'modal-retry-followup-held');
        expect(_dialog, findsNothing);
        refresh.release(_response());
        await f.waitResult(tester, issued['id'] as String);
        await f.capturePhase(tester, 'modal-retry-completed');
        expect(
          f.current.value.subscriptions.where((row) => row.id == issued['id']),
          hasLength(1),
        );
        expect(f.store.draftAttempts, hasLength(2));
        expect(tester.takeException(), isNull);
      }),
    );
  }
}

enum _MenuAction { pause, delete }

enum _RefreshRevocation { cover, replacement }

enum _Fault { none, writeThenFalse, writeThenThrow }

String _menuLabel(_MenuAction action) => action == _MenuAction.delete
    ? NotificationUiCopy.menuDelete
    : (NotificationUiCopy.isEn ? 'Pause' : '暂停');

Finder _menuItems() =>
    find.byWidgetPredicate((widget) => widget is PopupMenuItem<String>);
Finder _menuItem(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byWidgetPredicate((widget) => widget is PopupMenuItem<String>),
);

Finder _card([String name = _name]) =>
    find.ancestor(of: find.text(name), matching: find.byType(AppSurfaceCard));

Future<void> _openMenu(WidgetTester tester, String name) async {
  final scrollable = find
      .descendant(
        of: find.byType(IntegrationsScreen),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
      )
      .first;
  await tester.scrollUntilVisible(
    find.text(name),
    160,
    scrollable: scrollable,
    maxScrolls: 20,
  );
  final menu = find.descendant(
    of: _card(name),
    matching: find.byWidgetPredicate(
      (widget) => widget is PopupMenuButton<String>,
    ),
  );
  expect(menu, findsOneWidget);
  await tester.ensureVisible(menu);
  await tester.tap(menu);
  await tester.pumpAndSettle(
    const Duration(milliseconds: 50),
    EnginePhase.sendSemanticsUpdate,
    _timeout,
  );
  expect(_menuItems(), findsWidgets);
}

VoidCallback _retainMenuAction(WidgetTester tester, String name, Finder item) {
  final control = find.descendant(
    of: _card(name),
    matching: find.byWidgetPredicate(
      (widget) => widget is PopupMenuButton<String>,
    ),
  );
  final callback = tester.widget<PopupMenuButton<String>>(control).onSelected!;
  final value = tester.widget<PopupMenuItem<String>>(item).value!;
  final element = tester.element(item);
  final popup = ModalRoute.of(element)!;
  final navigator = Navigator.of(element);
  return () {
    // A product may dismiss a revoked menu. Its already queued selection must
    // still be unable to acquire the new source's authority.
    if (popup.isActive) navigator.removeRoute(popup);
    callback(value);
  };
}

Finder _globalRefresh() => find.ancestor(
  of: find.text(NotificationUiCopy.refreshAction),
  matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
);

Finder _primary() =>
    find.descendant(of: _dialog, matching: find.byType(FilledButton));
ButtonStyleButton _button(WidgetTester tester, Finder finder) =>
    tester.widget<ButtonStyleButton>(finder);
Finder _field(String label) => find.descendant(
  of: _dialog,
  matching: find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  ),
);

List<TextEditingValue> _fieldValues(WidgetTester tester) => [
  tester
      .widget<TextField>(_field(NotificationUiCopy.subscriptionNameLabel))
      .controller!
      .value,
  tester
      .widget<TextField>(_field(NotificationUiCopy.icsUrlLabel))
      .controller!
      .value,
];

Future<List<TextEditingValue>> _enterDraft(WidgetTester tester) async {
  await tester.enterText(
    _field(NotificationUiCopy.subscriptionNameLabel),
    _draftName,
  );
  await tester.enterText(_field(NotificationUiCopy.icsUrlLabel), _draftUrl);
  for (final label in [
    NotificationUiCopy.subscriptionNameLabel,
    NotificationUiCopy.icsUrlLabel,
  ]) {
    final controller = tester.widget<TextField>(_field(label)).controller!;
    controller.selection = TextSelection(
      baseOffset: 1,
      extentOffset: controller.text.length - 1,
    );
  }
  await tester.pump();
  return _fieldValues(tester);
}

String _textCopy(Text text) => text.data ?? text.textSpan?.toPlainText() ?? '';

Finder _pauseFailureRetry() => find.descendant(
  of: _card(),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is IconButton &&
        widget.tooltip == (NotificationUiCopy.isEn ? 'Retry pause' : '重试暂停'),
  ),
);

Future<VoidCallback> _rejectPauseAndRetainRetry(
  WidgetTester tester,
  _Fixture f,
) async {
  final held = f.store.holdNext(_key, fault: _Fault.writeThenFalse);
  await _openMenu(tester, _name);
  await tester.tap(_menuItem(_menuLabel(_MenuAction.pause)));
  await _until(
    tester,
    () => held.started.isCompleted,
    'Pause failure ACK started',
  );
  held.release();
  await f.drain(tester);
  await _until(
    tester,
    () => _menuItems().evaluate().isEmpty,
    'Pause failure menu dismissed',
  );
  _actionFailureFeedback(tester, _MenuAction.pause, const <String>{});
  expect(_pauseFailureRetry(), findsOneWidget);
  return tester.widget<IconButton>(_pauseFailureRetry()).onPressed!;
}

Future<void> _invokeRetainedRetry(
  WidgetTester tester,
  VoidCallback callback,
) async {
  // Preserve the runtime Future so setState-after-dispose cannot become an
  // unobserved asynchronous failure behind a void callback type.
  final completion = (callback as dynamic)();
  if (completion is Future) {
    await tester.runAsync(() => completion.timeout(_timeout));
  }
}

Set<String> _feedbackBaseline(WidgetTester tester) =>
    tester.widgetList<Text>(find.byType(Text)).map(_textCopy).toSet();

String _applicationCopy(String raw) {
  for (final literal in [
    _name,
    _recreatedName,
    _draftName,
    _draftUrl,
    'https://feed.test/existing.ics',
  ]) {
    raw = raw.replaceAll(literal.trim(), '');
  }
  return raw.trim();
}

class _ActionFailureReceipt {
  _ActionFailureReceipt(this.owner, this.raw);
  final Element owner;
  final String raw;
  String get copy => _applicationCopy(raw);
}

bool _meansActionFailure(String copy, _MenuAction action) {
  // Bind failure to the intended operation within a clause. A refresh failure
  // mentioning an already paused/deleted source is not this action's receipt.
  final actionWord = action == _MenuAction.pause
      ? r'(?:pause|pausing|disable|disabling)'
      : r'(?:delete|deleting|deletion|remove|removing|removal)';
  final passiveAction = action == _MenuAction.pause
      ? r'(?:paused|disabled)'
      : r'(?:deleted|removed)';
  final actionZh = action == _MenuAction.pause ? r'(?:暂停|停用)' : r'(?:删除|移除)';
  const failureBefore =
      r'(?:failed|unable|could not|couldn\x27t|cannot|can\x27t)';
  const failureAfter = r'(?:failed|failure|unsuccessful)';
  final failureEn = RegExp(
    '\\b$failureBefore\\s+(?:(?:to\\s+)?$actionWord|(?:to\\s+)?be\\s+$passiveAction)\\b|'
    '\\b$actionWord\\b[^.!?;；\\n]*\\b$failureAfter\\b',
    caseSensitive: false,
  );
  final failureZh = RegExp(
    '$actionZh[^。！？.!?;；\\n]*(?:失败|无法|未能)|(?:失败|无法|未能)[^。！？.!?;；\\n]*$actionZh',
  );
  final retry = RegExp(r'\b(?:retry|try again)\b|重试|再试', caseSensitive: false);
  return retry.hasMatch(copy) &&
      (failureEn.hasMatch(copy) || failureZh.hasMatch(copy));
}

List<_ActionFailureReceipt> _ownedActionFailureReceipts(
  WidgetTester tester,
  _MenuAction action,
  Set<String> baseline, {
  Element? retainedOwner,
}) {
  final candidates = <_ActionFailureReceipt>[];
  final sourceCards = _card().evaluate().toSet();
  final hosts = <Element>{
    ...sourceCards,
    ...find.byType(SnackBar).evaluate(),
    ...find.byType(MaterialBanner).evaluate(),
  };
  for (final host in hosts) {
    if (retainedOwner != null && !identical(host, retainedOwner)) continue;
    final scope = find.byElementPredicate(
      (element) => identical(element, host),
    );
    final hostCopy = tester
        .widgetList<Text>(
          find.descendant(of: scope, matching: find.byType(Text)),
        )
        .map(_textCopy)
        .toList();
    // The source card owns its inline message. Global notice hosts must name
    // this source explicitly, including a separate banner title when present.
    final ownsSource =
        sourceCards.contains(host) ||
        hostCopy.any(
          (raw) =>
              raw.contains(_name) ||
              raw.contains('https://feed.test/existing.ics'),
        );
    for (final raw in hostCopy) {
      if (!ownsSource ||
          baseline.contains(raw) ||
          !_meansActionFailure(_applicationCopy(raw), action)) {
        continue;
      }
      candidates.add(_ActionFailureReceipt(host, raw));
    }
  }
  return candidates;
}

_ActionFailureReceipt _actionFailureFeedback(
  WidgetTester tester,
  _MenuAction action,
  Set<String> baseline, {
  Element? retainedOwner,
}) {
  final candidates = _ownedActionFailureReceipts(
    tester,
    action,
    baseline,
    retainedOwner: retainedOwner,
  );
  expect(
    candidates,
    hasLength(1),
    reason:
        'the rejected ${action.name} ACK needs one newly introduced source-owned action failure with retry guidance',
  );
  final receipt = candidates.single;
  for (final diagnostic in [
    'PRIVATE',
    'StateError',
    'Preference persistence failed',
    'IcsStorageIndeterminate',
  ]) {
    expect(receipt.raw, isNot(contains(diagnostic)));
  }
  return receipt;
}

void _expectLiteralSourceLabels() {
  expect(
    find.descendant(of: _card(), matching: find.text(_name)),
    findsOneWidget,
  );
  expect(
    find.descendant(
      of: _card(),
      matching: find.text('https://feed.test/existing.ics'),
    ),
    findsOneWidget,
  );
}

List<Map<String, dynamic>> _rows(CalendarSyncProvider provider) =>
    provider.subscriptions.map((row) => row.toJson()).toList();
List<Map<String, dynamic>> _decodeRows(String? raw) =>
    (jsonDecode(raw ?? '[]') as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();

Future<void> _frames(WidgetTester tester) async {
  // Fixed frames also finish cover animations when a broken busy spinner never
  // settles. Do not use pumpAndSettle around intentionally held operations.
  for (var index = 0; index < 6; index++) {
    await tester.pump(const Duration(milliseconds: 75));
  }
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump();
}

Future<void> _until(
  WidgetTester tester,
  bool Function() done,
  String reason,
) async {
  for (var index = 0; index < 40 && !done(); index++) {
    await _frames(tester);
  }
  expect(done(), isTrue, reason: reason);
}

Future<void> _withFixture(
  WidgetTester tester,
  String brand,
  String caseName,
  Future<void> Function(_Fixture) body,
) async {
  final feed = _Feed();
  await http.runWithClient(() async {
    final f = await _mount(tester, brand, feed, caseName);
    try {
      await body(f);
    } catch (_) {
      try {
        await f.capturePhase(tester, 'failure-diagnostic');
      } catch (_) {
        // Evidence failures must not replace the original behavioral failure.
      }
      rethrow;
    }
  }, () => MockClient(feed.respond));
}

Future<_Fixture> _mount(
  WidgetTester tester,
  String brand,
  _Feed feed,
  String caseName,
) async {
  final previousStore = SharedPreferencesStorePlatform.instance;
  final previousLocale = I18n.current;
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await tester.runAsync(
    () => AccountLocalDataCleaner.clearSharedPreferences().timeout(_timeout),
  );
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final f = (await tester.runAsync(
    () async => _Fixture(brand, feed, caseName),
  ))!;
  SharedPreferencesStorePlatform.instance = f.store;
  I18n.setLocale(AppLocale.zh);
  addTearDown(() => f.close(tester, previousStore, previousLocale));
  await tester.runAsync(() async {
    await loadWeeklyReviewScreenshotFonts();
    f.prefs = await SharedPreferences.getInstance();
    await f.theme.loadFromStorage().timeout(_timeout);
    await f.locale.loadFromStorage().timeout(_timeout);
    await f.calendar.loadFromStorage().timeout(_timeout);
    await f.locations.loadFromStorage().timeout(_timeout);
  });
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    ValueListenableBuilder<CalendarSyncProvider>(
      valueListenable: f.current,
      builder: (context, calendar, _) => MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>.value(value: f.theme),
          ChangeNotifierProvider<LocaleProvider>.value(value: f.locale),
          ChangeNotifierProvider<CalendarSyncProvider>.value(value: calendar),
          ChangeNotifierProvider<LocationReminderProvider>.value(
            value: f.locations,
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
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context),
                child: RepaintBoundary(key: f.capture.key, child: child!),
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
  await tester.pumpAndSettle(
    const Duration(milliseconds: 50),
    EnginePhase.sendSemanticsUpdate,
    _timeout,
  );
  expect(f.theme.brand.id, brand);
  expect(f.parentRoute.isCurrent, isTrue);
  expect(find.byType(IntegrationsScreen), findsOneWidget);
  expect(tester.takeException(), isNull);
  f.store.writes.clear();
  return f;
}

class _Fixture {
  _Fixture(this.initialBrand, this.feed, String caseName) {
    capture = IcsVisualCapture(initialBrand: initialBrand, caseName: caseName);
    originalRaw = '[\n${jsonEncode(existing.toJson())}\n]\n';
    originalCache =
        '[\n${jsonEncode({'id': 'ics_existing_confirmed@test', 'title': 'Confirmed 用户事件', 'date': '2026-11-08T10:00:00.000', 'timeHour': 10, 'timeMinute': 0})}\n]\n';
    store = _Store(initialBrand, originalRaw, originalCache);
    current = ValueNotifier(calendar);
    calendars.add(calendar);
  }
  final String initialBrand;
  late final IcsVisualCapture capture;
  final _Feed feed;
  final calendar = CalendarSyncProvider();
  final theme = ThemeProvider();
  final locale = LocaleProvider();
  final locations = LocationReminderProvider();
  final notifications = NotificationService();
  final calendars = <CalendarSyncProvider>[];
  final navigator = GlobalKey<NavigatorState>();
  final existing = IcsSubscription(
    id: 'existing',
    name: _name,
    url: 'https://feed.test/existing.ics',
    lastSyncedAt: DateTime.utc(2026, 11, 8),
  );
  late final _Store store;
  late final ValueNotifier<CalendarSyncProvider> current;
  late final String originalRaw;
  late final String originalCache;
  late final SharedPreferences prefs;
  late MaterialPageRoute<void> parentRoute;
  ModalRoute<dynamic>? modalRoute;
  MaterialPageRoute<void>? coverRoute;

  Future<CalendarSyncProvider> peer(WidgetTester tester) async {
    final result = (await tester.runAsync(() async {
      final peer = CalendarSyncProvider();
      calendars.add(peer);
      await peer.loadFromStorage().timeout(_timeout);
      return peer;
    }))!;
    return result;
  }

  Future<MaterialPageRoute<void>> cover(WidgetTester tester) async {
    final route = MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('Unrelated covering route')),
    );
    coverRoute = route;
    unawaited(navigator.currentState!.push<void>(route));
    await _frames(tester);
    expect(route.isCurrent, isTrue);
    return route;
  }

  Future<void> uncover(
    WidgetTester tester,
    MaterialPageRoute<void> route,
  ) async {
    expect(route.isCurrent, isTrue);
    navigator.currentState!.pop();
    await _until(
      tester,
      () =>
          !route.isActive &&
          find.text('Unrelated covering route').evaluate().isEmpty,
      'cover reverse transition completed',
    );
    expect(find.text('Unrelated covering route'), findsNothing);
  }

  Future<void> drain(WidgetTester tester) async {
    await _frames(tester);
    await tester.runAsync(
      () => AccountPreferenceWrites.drain().timeout(_timeout),
    );
    await _frames(tester);
  }

  Future<void> waitResult(WidgetTester tester, String id) async {
    await _until(
      tester,
      () =>
          current.value.icsRefreshResults[id]?.status ==
              IcsRefreshStatus.refreshed &&
          !current.value.isSyncing,
      'new owned refresh result',
    );
    await drain(tester);
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
    });
    await _frames(tester);
  }

  Future<void> capturePhase(WidgetTester tester, String phase) async {
    final menuElements = _menuItems().evaluate();
    final menuRoute = menuElements.isEmpty
        ? null
        : ModalRoute.of(menuElements.first);
    final metadata = (await tester.runAsync(
      () async => <String, Object?>{
        'rawStore': await snapshot(),
        'memoryRows': _rows(current.value),
        'outgoingRows': _rows(calendar),
        'memoryEventTitles': current.value
            .allEvents()
            .map((event) => event.title)
            .toList(),
        'writes': List<String>.from(store.writes),
        'draftAttempts': store.draftAttempts,
        'httpRequests': feed.requests.map((uri) => uri.toString()).toList(),
        'origin': {
          'provider': identical(current.value, calendar)
              ? 'initial'
              : 'replacement',
          'lifetime': current.value.icsLifetimeGeneration,
          'outgoingLifetime': calendar.icsLifetimeGeneration,
          'accountBoundaryActive': AccountPreferenceWrites.isBoundaryActive,
          'parentCurrent': parentRoute.isCurrent,
          'modalCurrent': modalRoute?.isCurrent,
          'modalActive': modalRoute?.isActive,
          'coverCurrent': coverRoute?.isCurrent,
          'menuCurrent': menuRoute?.isCurrent,
        },
        'pending': {
          'isSyncing': current.value.isSyncing,
          'outgoingIsSyncing': calendar.isSyncing,
          'storageAcks': store._all
              .where(
                (gate) =>
                    gate.started.isCompleted && !gate._released.isCompleted,
              )
              .length,
          'queuedStorageAcks': store._next.values.fold<int>(
            0,
            (count, gates) => count + gates.length,
          ),
          'httpResponses': feed._all
              .where(
                (gate) =>
                    gate.started.isCompleted && !gate._released.isCompleted,
              )
              .length,
          'queuedHttpResponses': feed._next.length,
        },
        'needsReconciliation': current.value.icsStorageNeedsReconciliation,
        'results': current.value.icsRefreshResults.map(
          (id, result) => MapEntry(id, {
            'status': result.status.name,
            'eventCount': result.eventCount,
          }),
        ),
        'outgoingResults': calendar.icsRefreshResults.map(
          (id, result) => MapEntry(id, {
            'status': result.status.name,
            'eventCount': result.eventCount,
          }),
        ),
      },
    ))!;
    await capture.take(
      tester,
      phase,
      actualBrand: theme.brand.id,
      locale: I18n.current.name,
      metadata: metadata,
    );
  }

  Future<Map<String, String?>> snapshot() async => {
    _key: await store.raw(_key),
    _cacheKey: await store.raw(_cacheKey),
  };

  Future<void> expectRaw(Map<String, String?> raw) async {
    for (final entry in raw.entries) {
      expect(
        await store.raw(entry.key),
        entry.value,
        reason: 'backing ${entry.key}',
      );
      expect(
        prefs.getString(entry.key),
        entry.value,
        reason: 'cached ${entry.key}',
      );
    }
    await prefs.reload();
    for (final entry in raw.entries) {
      expect(
        prefs.getString(entry.key),
        entry.value,
        reason: 'reloaded ${entry.key}',
      );
    }
  }

  Future<void> expectBaseline() =>
      expectRaw({_key: originalRaw, _cacheKey: originalCache});

  Future<void> close(
    WidgetTester tester,
    SharedPreferencesStorePlatform previousStore,
    AppLocale previousLocale,
  ) async {
    try {
      AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      await tester.pumpWidget(const SizedBox.shrink());
      store.releaseAll();
      feed.releaseAll();
      store.clearUnusedSteps();
      await drain(tester);
      await tester.runAsync(
        () =>
            AccountLocalDataCleaner.clearSharedPreferences().timeout(_timeout),
      );
    } finally {
      for (final provider in calendars) {
        provider.dispose();
      }
      current.dispose();
      theme.dispose();
      locale.dispose();
      locations.dispose();
      notifications.dispose();
      tester.view.reset();
      I18n.setLocale(previousLocale);
      SharedPreferences.resetStatic();
      SharedPreferencesStorePlatform.instance = previousStore;
    }
  }
}

class _WriteGate {
  _WriteGate(this.fault);
  final _Fault fault;
  final started = Completer<void>();
  final _released = Completer<void>();
  void release() {
    if (!_released.isCompleted) _released.complete();
  }
}

class _Store extends InMemorySharedPreferencesStore {
  _Store(String brand, String raw, String cache)
    : super.withData({
        'flutter.active_brand': brand,
        'flutter.theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
        'flutter.duoyi_locale_v1': 'zh',
        'flutter.$_key': raw,
        'flutter.$_cacheKey': cache,
      });
  final writes = <String>[];
  final snapshots = <List<Map<String, dynamic>>>[];
  final _next = <String, List<_WriteGate>>{};
  final _all = <_WriteGate>[];
  List<Map<String, dynamic>> get draftAttempts => snapshots
      .expand((rows) => rows)
      .where(
        (row) =>
            row['name'] == _draftName.trim() && row['lastSyncedAt'] == null,
      )
      .toList();

  _WriteGate holdNext(String key, {_Fault fault = _Fault.none}) {
    final gate = _WriteGate(fault);
    _next.putIfAbsent(key, () => []).add(gate);
    _all.add(gate);
    return gate;
  }

  void releaseAll() {
    for (final gate in _all) {
      gate.release();
    }
  }

  void clearUnusedSteps() => _next.clear();
  Future<String?> raw(String key) async =>
      (await getAll())['flutter.$key'] as String?;

  Future<bool> write(String key, Future<bool> Function() operation) async {
    final local = key.startsWith('flutter.') ? key.substring(8) : key;
    if (local != _key && !local.startsWith('duoyi_ics_events_')) {
      return operation();
    }
    writes.add(local);
    final pending = _next[local];
    final gate = pending == null || pending.isEmpty
        ? null
        : pending.removeAt(0);
    if (gate != null) {
      gate.started.complete();
      await gate._released.future;
    }
    final result = await operation();
    if (gate?.fault == _Fault.writeThenFalse) return false;
    if (gate?.fault == _Fault.writeThenThrow) {
      throw StateError('PRIVATE synthetic ICS mutation write failure');
    }
    return result;
  }

  @override
  Future<bool> setValue(String type, String key, Object value) {
    if (key == 'flutter.$_key') snapshots.add(_decodeRows(value as String));
    return write(key, () => super.setValue(type, key, value));
  }

  @override
  Future<bool> remove(String key) => write(key, () => super.remove(key));
}

http.Response _response({String body = _emptyCalendar}) => http.Response(
  body,
  200,
  headers: {'content-type': 'text/calendar; charset=utf-8'},
);

class _HttpGate {
  final started = Completer<void>();
  final _released = Completer<http.Response>();
  void release(http.Response response) {
    if (!_released.isCompleted) _released.complete(response);
  }
}

class _Feed {
  final requests = <Uri>[];
  final _next = <_HttpGate>[];
  final _all = <_HttpGate>[];

  _HttpGate holdNext() {
    final gate = _HttpGate();
    _next.add(gate);
    _all.add(gate);
    return gate;
  }

  Future<http.Response> respond(http.Request request) async {
    requests.add(request.url);
    if (_next.isEmpty) return _response();
    final gate = _next.removeAt(0);
    gate.started.complete();
    return gate._released.future;
  }

  void releaseAll() {
    for (final gate in _all) {
      gate.release(_response());
    }
  }
}
