// ignore_for_file: depend_on_referenced_packages

// Prepared against ICS frontend contract 3 / AGY task 19 and the frozen
// frontend preimage. Production CalendarSyncProvider/storage are never stubbed.
// No intermediate integrations_screen edits were read during preparation.
// Locators were finalized against the terminal AGY task-19 public controls.
// Main owns formatting, guarded execution and any evidence capture.
import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/design_tokens.dart';
import 'package:duoyi/core/i18n.dart';
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
import 'package:flutter/semantics.dart';
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
const _timeout = Duration(seconds: 5);
const _open = ValueKey('open-ics-subscription-commit-fixture');
const _literalName = '  Literal 用户 calendar / keep spaces  ';
const _literalUrl = '  https://feed.test/new.ics?literal=keep  ';
const _emptyCalendar = 'BEGIN:VCALENDAR\nVERSION:2.0\nEND:VCALENDAR\n';
final _dialog = find.byType(AppDialog);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final brand in ['defaultBrand', 'liquidGlass']) {
    testWidgets(
      '$brand held save keeps its draft/modal and rejects queued duplicate taps',
      (tester) => _withFixture(tester, brand, 'held-save', (f) async {
        final semantics = tester.ensureSemantics();
        try {
          await _openDraft(tester);
          final values = await _enterDraft(tester);
          final element = tester.element(_dialog);
          final route = ModalRoute.of(element)!;
          final save = f.store.holdNext();
          final network = f.feed.holdNext();
          f.feed.dialogRoute = route;
          final queuedSubmit = _callback(tester, _primary());
          queuedSubmit();
          queuedSubmit();
          await _until(
            tester,
            () => save.started.isCompleted,
            'first list ACK held',
          );

          await f.capturePhase(tester, 'save-held');
          expect(
            _caption(tester.element(_primary())).split('\n'),
            contains(I18n.tr('action.add')),
            reason: 'the first pending save is Add, not a rejected-save Retry',
          );
          final waitingZh = _expectWaiting(tester);
          _expectDraft(tester, values);
          expect(tester.element(_dialog), same(element));
          expect(ModalRoute.of(tester.element(_dialog)), same(route));
          expect(_onPressed(tester, _primary()), isNull);
          expect(f.store.draftAttempts, hasLength(1));
          expect(f.calendar.subscriptions.map((row) => row.id), ['existing']);
          expect(await f.store.raw(_key), f.originalRaw);
          expect(f.feed.requests, isEmpty);

          await f.switchPresentation(tester);
          expect(_expectWaiting(tester), isNot(waitingZh));
          _expectDraft(tester, values);
          _expectDialogTheme(tester, f);
          queuedSubmit();
          await _frames(tester);
          expect(f.store.draftAttempts, hasLength(1));
          expect(f.feed.requests, isEmpty);
          final issued = Map<String, dynamic>.from(
            f.store.draftAttempts.single,
          );

          save.release();
          await f.drain(tester);
          await _until(
            tester,
            () => network.started.isCompleted,
            'targeted followup dispatched',
          );
          expect(_dialog, findsNothing);
          expect(f.feed.dialogWasCurrentAtDispatch, [false]);
          expect(f.feed.requests, [Uri.parse(_literalUrl.trim())]);
          expect(
            f.calendar.subscriptions.where((row) => row.id == issued['id']),
            hasLength(1),
          );
          network.release(_response());
          await f.waitResult(
            tester,
            issued['id'] as String,
            IcsRefreshStatus.refreshed,
          );
          await _expectAccepted(f, issued);
          expect(f.store.draftAttempts, hasLength(1));
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      }),
    );

    for (final failure in [_Failure.writeThenFalse, _Failure.writeThenThrow]) {
      testWidgets(
        '$brand ${failure.name} restores storage and retains one stable ID for corrected retry',
        (tester) => _withFixture(tester, brand, 'rejection-${failure.name}', (
          f,
        ) async {
          await _openDraft(tester);
          final values = await _enterDraft(tester);
          final route = ModalRoute.of(tester.element(_dialog))!;
          final held = f.store.holdNext(failure: failure);
          _callback(tester, _primary())();
          await _until(
            tester,
            () => held.started.isCompleted,
            'rejected save held',
          );
          held.release();
          await f.drain(tester);
          await f.capturePhase(tester, 'save-rejected');

          _expectDraft(tester, values);
          expect(ModalRoute.of(tester.element(_dialog)), same(route));
          expect(_onPressed(tester, _primary()), isNotNull);
          expect(f.calendar.subscriptions.map((row) => row.id), ['existing']);
          await f.expectBaseline();
          expect(f.feed.requests, isEmpty);
          expect(f.store.draftAttempts, hasLength(1));
          final rejected = Map<String, dynamic>.from(
            f.store.draftAttempts.single,
          );
          final feedbackZh = _safeFeedback(tester, _dialog);
          expect(feedbackZh, matches(RegExp(r'[\u3400-\u9fff]')));

          await f.switchPresentation(tester);
          _expectDraft(tester, values);
          _expectDialogTheme(tester, f);
          final feedbackEn = _safeFeedback(tester, _dialog);
          expect(feedbackEn, isNot(feedbackZh));
          expect(feedbackEn, isNot(matches(RegExp(r'[\u3400-\u9fff]'))));
          expect(
            f.store.draftAttempts,
            hasLength(1),
            reason: 'locale/theme never replays a save',
          );

          // A rejected unconfirmed draft may be corrected while retaining its ID.
          final corrected = await _enterDraft(
            tester,
            url: '  https://feed.test/corrected.ics  ',
          );
          final retry = f.store.holdNext();
          final network = f.feed.holdNext();
          _callback(tester, _primary())();
          await _until(
            tester,
            () => retry.started.isCompleted,
            'explicit retry held',
          );
          _expectDraft(tester, corrected);
          expect(f.store.draftAttempts, hasLength(2));
          final retried = Map<String, dynamic>.from(f.store.draftAttempts.last);
          expect(retried['id'], rejected['id']);
          expect(retried['name'], _literalName.trim());
          expect(retried['url'], 'https://feed.test/corrected.ics');
          expect(f.feed.requests, isEmpty);
          retry.release();
          await f.drain(tester);
          await _until(
            tester,
            () => network.started.isCompleted,
            'retry followup dispatched',
          );
          expect(_dialog, findsNothing);
          expect(f.feed.requests, [Uri.parse(retried['url'] as String)]);
          network.release(_response());
          await f.waitResult(
            tester,
            retried['id'] as String,
            IcsRefreshStatus.refreshed,
          );
          await _expectAccepted(f, retried);
          expect(f.store.draftAttempts, hasLength(2));
          expect(tester.takeException(), isNull);
        }),
      );
    }

    testWidgets(
      '$brand retained validation translates live and actions fit enlarged keyboard window',
      (tester) => _withFixture(tester, brand, 'keyboard-validation', (f) async {
        await _openDraft(tester);
        final values = await _enterDraft(tester, name: '', url: 'https://');
        final route = ModalRoute.of(tester.element(_dialog))!;
        _callback(tester, _primary())();
        await _frames(tester);
        await f.capturePhase(tester, 'validation');
        expect(_fieldErrors(tester), [
          NotificationUiCopy.nameRequiredError,
          NotificationUiCopy.invalidUrlError,
        ]);
        expect(f.store.draftAttempts, isEmpty);
        expect(f.feed.requests, isEmpty);

        f.setView(tester, const _View(Size(320, 844), 1.6, 260));
        await f.switchPresentation(tester);
        _expectDraft(tester, values);
        expect(ModalRoute.of(tester.element(_dialog)), same(route));
        expect(_fieldErrors(tester), [
          NotificationUiCopy.nameRequiredError,
          NotificationUiCopy.invalidUrlError,
        ]);
        _expectDialogTheme(tester, f);
        await _expectReachable(tester, _primary());
        await _expectReachable(tester, _cancel());
        await f.expectBaseline();
        expect(f.store.draftAttempts, isEmpty);
        expect(tester.takeException(), isNull);
      }),
    );

    testWidgets(
      '$brand indeterminate save requires explicit recovery then a separate stable-ID retry',
      (tester) => _withFixture(tester, brand, 'uncertain-save', (f) async {
        await _openDraft(tester);
        final values = await _enterDraft(tester);
        final route = ModalRoute.of(tester.element(_dialog))!;
        f.store.plan([
          _Step(_Failure.writeThenFalse),
          _Step(_Failure.beforeFalse),
        ]);
        _callback(tester, _primary())();
        await f.drain(tester);
        await f.capturePhase(tester, 'save-uncertain');
        expect(f.calendar.icsStorageNeedsReconciliation, isTrue);
        expect(f.calendar.subscriptions.map((row) => row.id), ['existing']);
        expect(f.store.draftAttempts, hasLength(1));
        final issued = Map<String, dynamic>.from(f.store.draftAttempts.single);
        _expectDraft(tester, values);
        _safeFeedback(tester, _dialog);
        await f.switchPresentation(tester);
        _expectDraft(tester, values);
        _expectDialogTheme(tester, f);
        _safeFeedback(tester, _dialog);

        final recovery = _recovery();
        final queuedRecovery = _callback(tester, recovery);
        final heldRecovery = f.store.holdNext();
        await _tap(tester, recovery);
        queuedRecovery();
        await _until(
          tester,
          () => heldRecovery.started.isCompleted,
          'explicit recovery held',
        );
        await f.capturePhase(tester, 'recovery-held');
        _expectDraft(tester, values);
        expect(_onPressed(tester, _primary()), isNull);
        expect(_onPressed(tester, recovery), isNull);
        expect(f.store.draftAttempts, hasLength(1));
        expect(f.feed.requests, isEmpty);
        heldRecovery.release();
        await f.drain(tester);
        await f.capturePhase(tester, 'recovered-no-replay');

        expect(f.calendar.icsStorageNeedsReconciliation, isFalse);
        expect(ModalRoute.of(tester.element(_dialog)), same(route));
        _expectDraft(tester, values);
        await f.expectBaseline();
        expect(_onPressed(tester, _primary()), isNotNull);
        expect(
          f.store.draftAttempts,
          hasLength(1),
          reason: 'reconciliation must not replay add',
        );
        expect(f.feed.requests, isEmpty);

        final retry = f.store.holdNext();
        final network = f.feed.holdNext();
        await _tap(tester, _primary());
        await _until(
          tester,
          () => retry.started.isCompleted,
          'separate save retry held',
        );
        expect(f.store.draftAttempts, hasLength(2));
        expect(f.store.draftAttempts.last, issued);
        expect(f.feed.requests, isEmpty);
        retry.release();
        await f.drain(tester);
        await _until(
          tester,
          () => network.started.isCompleted,
          'recovered save refresh dispatched',
        );
        expect(_dialog, findsNothing);
        network.release(_response());
        await f.waitResult(
          tester,
          issued['id'] as String,
          IcsRefreshStatus.refreshed,
        );
        await _expectAccepted(f, issued);
        expect(tester.takeException(), isNull);
      }),
    );

    testWidgets(
      '$brand accepted save with failed followup offers row Refresh retry without another add',
      (tester) => _withFixture(tester, brand, 'refresh-retry', (f) async {
        await _openDraft(tester);
        await _enterDraft(tester);
        final save = f.store.holdNext();
        final network = f.feed.holdNext();
        _callback(tester, _primary())();
        await _until(
          tester,
          () => save.started.isCompleted,
          'save held before followup',
        );
        expect(f.feed.requests, isEmpty);
        save.release();
        await f.drain(tester);
        await _until(
          tester,
          () => network.started.isCompleted,
          'accepted save followup held',
        );
        final issued = Map<String, dynamic>.from(f.store.draftAttempts.single);
        final id = issued['id'] as String;
        expect(_dialog, findsNothing);
        expect(
          f.calendar.subscriptions.where((row) => row.id == id),
          hasLength(1),
        );
        network.release(
          _response(status: 503, body: 'PRIVATE upstream feed unavailable'),
        );
        await f.waitResult(tester, id, IcsRefreshStatus.httpFailure);
        expect(
          f.calendar.subscriptions
              .singleWhere((row) => row.id == id)
              .lastSyncedAt,
          isNull,
        );
        expect(await f.store.raw('duoyi_ics_events_$id'), isNull);
        expect(f.store.draftAttempts, hasLength(1));
        final row = await _revealSubscription(tester);
        await f.capturePhase(tester, 'refresh-http-failed');
        final feedbackZh = _safeFeedback(tester, row);
        final retryZh = _rowRefresh(row);
        expect(_onPressed(tester, retryZh), isNotNull);

        await f.switchPresentation(tester);
        expect(_safeFeedback(tester, _subscriptionCard()), isNot(feedbackZh));
        expect(f.feed.requests, hasLength(1));
        expect(find.text(_literalName.trim()), findsOneWidget);
        expect(find.text(_literalUrl.trim()), findsOneWidget);
        final refresh = f.feed.holdNext();
        await _tap(tester, _rowRefresh(_subscriptionCard()));
        await _until(
          tester,
          () => refresh.started.isCompleted,
          'row refresh retry held',
        );
        expect(_dialog, findsNothing);
        expect(f.store.draftAttempts, hasLength(1));
        expect(f.feed.requests, [
          Uri.parse(_literalUrl.trim()),
          Uri.parse(_literalUrl.trim()),
        ]);
        refresh.release(_response());
        await f.waitResult(tester, id, IcsRefreshStatus.refreshed);
        expect(f.calendar.icsRefreshResults[id]!.eventCount, 0);
        expect(f.store.draftAttempts, hasLength(1));
        await _expectAccepted(f, issued);
        expect(tester.takeException(), isNull);
      }),
    );
  }

  for (final invalidation in _Invalidation.values) {
    testWidgets(
      'pending real ICS save cancels ${invalidation.name} origin without stale writes or fetch',
      (tester) => _withFixture(
        tester,
        'defaultBrand',
        'cancel-${invalidation.name}',
        (f) async {
          await _openDraft(tester);
          await _enterDraft(tester);
          final route = ModalRoute.of(tester.element(_dialog))!;
          final save = f.store.holdNext();
          _callback(tester, _primary())();
          await _until(
            tester,
            () => save.started.isCompleted,
            'outgoing save held',
          );
          expect(f.store.draftAttempts, hasLength(1));
          await f.invalidate(tester, invalidation, route);
          MaterialPageRoute<void>? cover;
          if (invalidation == _Invalidation.modal ||
              invalidation == _Invalidation.back ||
              invalidation == _Invalidation.parent) {
            cover = MaterialPageRoute<void>(
              builder: (_) =>
                  const Scaffold(body: Text('Unrelated covering route')),
            );
            unawaited(f.navigator.currentState!.push<void>(cover));
            await _frames(tester);
          }
          save.release();
          await f.drain(tester);

          await f.expectBaseline();
          expect(
            f.calendar.subscriptions.any(
              (row) => row.name == _literalName.trim(),
            ),
            isFalse,
          );
          expect(
            f.current.value.subscriptions.any(
              (row) => row.name == _literalName.trim(),
            ),
            isFalse,
          );
          expect(f.feed.requests, isEmpty);
          expect(find.byType(SnackBar), findsNothing);
          if (cover != null) {
            expect(cover.isCurrent, isTrue);
            expect(find.text('Unrelated covering route'), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
        },
      ),
    );
  }
}

enum _Invalidation { modal, back, parent, account, replacement, lifetime }

enum _Failure { none, beforeFalse, writeThenFalse, writeThenThrow }

class _View {
  const _View(this.size, this.scale, this.keyboard);
  final Size size;
  final double scale;
  final double keyboard;
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
      await f.capturePhase(tester, 'failure-diagnostic');
      rethrow;
    }
  }, () => MockClient(feed.respond));
}

Future<void> _frames(WidgetTester tester) async {
  for (var index = 0; index < 4; index++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump();
}

Future<void> _until(
  WidgetTester tester,
  bool Function() done,
  String reason,
) async {
  for (var index = 0; index < 60 && !done(); index++) {
    await _frames(tester);
  }
  expect(done(), isTrue, reason: reason);
}

Finder _field(String label) => find.descendant(
  of: _dialog,
  matching: find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  ),
);

List<TextField> _fieldWidgets(WidgetTester tester) => [
  tester.widget<TextField>(_field(NotificationUiCopy.subscriptionNameLabel)),
  tester.widget<TextField>(_field(NotificationUiCopy.icsUrlLabel)),
];

Future<void> _openDraft(WidgetTester tester) async {
  final add = find.byTooltip(NotificationUiCopy.addIcsTooltip);
  expect(add, findsOneWidget);
  await tester.ensureVisible(add);
  await tester.tap(add);
  await tester.pumpAndSettle(
    const Duration(milliseconds: 50),
    EnginePhase.sendSemanticsUpdate,
    _timeout,
  );
  expect(_dialog, findsOneWidget);
  expect(
    find.text(NotificationUiCopy.addSubscriptionDialogTitle),
    findsOneWidget,
  );
}

Future<List<TextEditingValue>> _enterDraft(
  WidgetTester tester, {
  String name = _literalName,
  String url = _literalUrl,
}) async {
  await tester.enterText(
    _field(NotificationUiCopy.subscriptionNameLabel),
    name,
  );
  await tester.enterText(_field(NotificationUiCopy.icsUrlLabel), url);
  final fields = _fieldWidgets(tester);
  for (final field in fields) {
    final text = field.controller!.text;
    field.controller!.selection = text.isEmpty
        ? const TextSelection.collapsed(offset: 0)
        : TextSelection(
            baseOffset: text.length > 2 ? 1 : 0,
            extentOffset: text.length,
          );
  }
  await tester.pump();
  return fields.map((field) => field.controller!.value).toList();
}

void _expectDraft(WidgetTester tester, List<TextEditingValue> values) {
  expect(_dialog, findsOneWidget);
  expect(
    _fieldWidgets(tester).map((field) => field.controller!.value).toList(),
    values,
  );
}

List<String?> _fieldErrors(WidgetTester tester) =>
    _fieldWidgets(tester).map((field) => field.decoration?.errorText).toList();

String _caption(Element element) {
  final labels = <String>[];
  void visit(Element child) {
    final widget = child.widget;
    if (widget is Text) {
      labels.add(widget.data ?? widget.textSpan?.toPlainText() ?? '');
    }
    if (widget is Tooltip) labels.add(widget.message ?? '');
    if (widget is Semantics) labels.add(widget.properties.label ?? '');
    if (widget is IconButton) labels.add(widget.tooltip ?? '');
    child.visitChildElements(visit);
  }

  visit(element);
  return labels.join('\n');
}

final _recoveryWords = RegExp(
  r'recover|repair|reconcil|恢复|修复|重新确认',
  caseSensitive: false,
);

List<Element> _actionElements(Finder scope) => find
    .descendant(
      of: scope,
      matching: find.byWidgetPredicate(
        (widget) => widget is ButtonStyleButton || widget is IconButton,
      ),
    )
    .evaluate()
    .toList();

Finder _elementFinder(Element element) =>
    find.byElementPredicate((candidate) => identical(candidate, element));

Finder _primary() {
  final buttons = _actionElements(_dialog);
  final captions = {
    I18n.tr('action.add'),
    I18n.tr('action.save'),
    I18n.tr('action.retry'),
  };
  var matches = buttons
      .where(
        (element) =>
            _caption(element).split('\n').any(captions.contains) &&
            !_recoveryWords.hasMatch(_caption(element)),
      )
      .toList();
  if (matches.isEmpty) {
    // A pending primary may replace its ordinary caption with localized waiting.
    matches = buttons
        .where(
          (element) =>
              element.widget is FilledButton &&
              !_recoveryWords.hasMatch(_caption(element)),
        )
        .toList();
  }
  expect(matches, hasLength(1), reason: 'one owned Add/Save/Retry action');
  return _elementFinder(matches.single);
}

Finder _cancel() {
  final matches = _actionElements(_dialog)
      .where(
        (element) =>
            _caption(element).split('\n').contains(I18n.tr('action.cancel')),
      )
      .toList();
  expect(matches, hasLength(1));
  return _elementFinder(matches.single);
}

Finder _recovery() {
  final label = NotificationUiCopy.isEn ? 'Recover Storage' : '恢复存储';
  final matches = _actionElements(
    _dialog,
  ).where((element) => _caption(element).split('\n').contains(label)).toList();
  expect(
    matches,
    hasLength(1),
    reason: 'an explicit localized recovery control',
  );
  return _elementFinder(matches.single);
}

Finder _subscriptionCard() {
  final card = find.ancestor(
    of: find.text(_literalName.trim()),
    matching: find.byType(AppSurfaceCard),
  );
  expect(
    card,
    findsOneWidget,
    reason: 'scope retry to the saved subscription row',
  );
  return card;
}

Future<Finder> _revealSubscription(WidgetTester tester) async {
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
    find.text(_literalName.trim()),
    160,
    scrollable: scrollable,
    maxScrolls: 20,
  );
  final row = _subscriptionCard();
  await tester.ensureVisible(row);
  await _frames(tester);
  return row;
}

Finder _rowRefresh(Finder row) {
  final tooltip = NotificationUiCopy.isEn ? 'Retry refresh' : '重试刷新';
  final matches = _actionElements(row)
      .where(
        (element) =>
            element.widget is IconButton &&
            (element.widget as IconButton).tooltip == tooltip,
      )
      .toList();
  expect(
    matches,
    hasLength(1),
    reason: 'one row-owned Refresh/Retry action, not the global refresh',
  );
  return _elementFinder(matches.single);
}

VoidCallback? _onPressed(WidgetTester tester, Finder finder) =>
    switch (tester.widget<Widget>(finder)) {
      ButtonStyleButton widget => widget.onPressed,
      IconButton widget => widget.onPressed,
      _ => throw StateError('Expected an actionable button'),
    };

VoidCallback _callback(WidgetTester tester, Finder finder) {
  final callback = _onPressed(tester, finder);
  expect(callback, isNotNull);
  return callback!;
}

Future<void> _tap(WidgetTester tester, Finder action) async {
  expect(_onPressed(tester, action), isNotNull);
  await tester.ensureVisible(action);
  await _frames(tester);
  expect(action.hitTestable(), findsOneWidget);
  await tester.tap(action);
}

Future<void> _expectReachable(WidgetTester tester, Finder action) async {
  await tester.ensureVisible(action);
  await _frames(tester);
  expect(action.hitTestable(), findsOneWidget);
  final size = tester.view.physicalSize / tester.view.devicePixelRatio;
  final inset = MediaQuery.viewInsetsOf(tester.element(_dialog)).bottom;
  final viewport = Rect.fromLTWH(0, 0, size.width, size.height - inset);
  final rect = tester.getRect(action);
  expect(viewport.inflate(.1).contains(rect.topLeft), isTrue);
  expect(viewport.inflate(.1).contains(rect.bottomRight), isTrue);
}

Iterable<String> _ordinaryCopy() => {
  NotificationUiCopy.addSubscriptionDialogTitle,
  NotificationUiCopy.subscriptionNameLabel,
  NotificationUiCopy.icsUrlLabel,
  I18n.tr('action.add'),
  I18n.tr('action.save'),
  I18n.tr('action.retry'),
  I18n.tr('action.cancel'),
  NotificationUiCopy.refreshAction,
  'Active',
  'Paused',
  '已启用',
  '已暂停',
  _literalName,
  _literalName.trim(),
  _literalUrl,
  _literalUrl.trim(),
  'https://...',
};

String _stripOrdinary(String text) {
  var result = text;
  for (final caption in _ordinaryCopy()) {
    if (caption.isNotEmpty) result = result.replaceAll(caption, '');
  }
  return result.trim();
}

String _safeFeedback(WidgetTester tester, Finder scope) {
  final actionCopy = _actionElements(scope)
      .expand((element) => _caption(element).split('\n'))
      .map((text) => text.trim())
      .where((text) => text.isNotEmpty)
      .toSet();
  final messages = tester
      .widgetList<Text>(find.descendant(of: scope, matching: find.byType(Text)))
      .map((widget) => widget.data ?? widget.textSpan?.toPlainText() ?? '')
      .where((text) => !actionCopy.contains(text.trim()));
  final feedback = messages
      .map(_stripOrdinary)
      .where((text) => text.isNotEmpty)
      .join('\n');
  expect(
    feedback,
    isNotEmpty,
    reason:
        'semantic outcome has visible feedback beyond controls and user data',
  );
  for (final raw in [
    'PRIVATE',
    'StateError',
    'IcsStorageIndeterminate',
    'Preference persistence failed',
  ]) {
    expect(
      feedback,
      isNot(contains(raw)),
      reason: 'application feedback must not expose raw diagnostics',
    );
  }
  return feedback;
}

String _expectWaiting(WidgetTester tester) {
  final progress = find.descendant(
    of: _dialog,
    matching: find.byType(CircularProgressIndicator),
  );
  expect(progress, findsWidgets);
  expect(progress.first.hitTestable(), findsOneWidget);
  final labels = <String>[];
  void visit(SemanticsNode node) {
    labels.add(node.getSemanticsData().label);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(tester.getSemantics(_dialog));
  final waiting = labels
      .map(_stripOrdinary)
      .where((value) => RegExp(r'[A-Za-z]{3,}|[\u3400-\u9fff]').hasMatch(value))
      .join('\n');
  expect(
    waiting,
    isNotEmpty,
    reason: 'waiting is accessible beyond field/button captions',
  );
  expect(
    waiting,
    NotificationUiCopy.isEn
        ? isNot(matches(RegExp(r'[\u3400-\u9fff]')))
        : matches(RegExp(r'[\u3400-\u9fff]')),
  );
  return waiting;
}

void _expectDialogTheme(WidgetTester tester, _Fixture f) {
  final actual = Theme.of(tester.element(_dialog));
  final expected = f.theme.brand.theme;
  expect(actual.colorScheme, expected.colorScheme);
  expect(actual.brightness, expected.brightness);
  expect(
    actual.extension<AppSurfaceStyle>()?.cardFillColor,
    expected.extension<AppSurfaceStyle>()?.cardFillColor,
  );
  expect(
    actual.extension<AppSurfaceStyle>()?.navBarBlurSigma,
    expected.extension<AppSurfaceStyle>()?.navBarBlurSigma,
  );
}

Future<void> _expectAccepted(_Fixture f, Map<String, dynamic> issued) async {
  final raw = await f.store.raw(_key);
  final rows = _decodeRows(raw);
  expect(rows, hasLength(2));
  expect(rows.first, f.existing.toJson());
  final actual = rows.singleWhere((row) => row['id'] == issued['id']);
  for (final field in ['id', 'name', 'url', 'colorValue', 'enabled']) {
    expect(
      actual[field],
      issued[field],
      reason: 'one confirmed literal draft $field',
    );
  }
  expect(actual['lastSyncedAt'], isNotNull);
  expect(
    f.current.value.subscriptions.map((row) => row.toJson()).toList(),
    rows,
  );
  expect(await f.store.raw('duoyi_ics_events_existing'), f.originalCache);
  await f.prefs.reload();
  expect(f.prefs.getString(_key), raw);
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
  expect(f.theme.brand.id, brand);
  tester.view.physicalSize = f.view.value.size;
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
              builder: (context, child) => ValueListenableBuilder<_View>(
                valueListenable: f.view,
                builder: (context, view, _) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    size: view.size,
                    textScaler: TextScaler.linear(view.scale),
                    viewInsets: EdgeInsets.only(bottom: view.keyboard),
                  ),
                  child: RepaintBoundary(key: f.capture.key, child: child!),
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
  await tester.pumpAndSettle(
    const Duration(milliseconds: 50),
    EnginePhase.sendSemanticsUpdate,
    _timeout,
  );
  expect(find.byType(IntegrationsScreen), findsOneWidget);
  expect(f.parentRoute.isCurrent, isTrue);
  expect(find.byTooltip(NotificationUiCopy.addIcsTooltip), findsOneWidget);
  expect(f.store.draftAttempts, isEmpty);
  expect(tester.takeException(), isNull);
  return f;
}

class _Fixture {
  _Fixture(this.initialBrand, this.feed, String caseName) {
    capture = IcsVisualCapture(initialBrand: initialBrand, caseName: caseName);
    originalRaw = '[\n  ${jsonEncode(existing.toJson())}\n]\n';
    originalCache =
        '[\n  ${jsonEncode({'id': 'ics_existing_confirmed@test', 'title': 'Previously confirmed 用户事件', 'date': '2026-11-08T10:00:00.000', 'timeHour': 10, 'timeMinute': 0})}\n]\n';
    store = _Store(initialBrand, originalRaw, originalCache);
    current = ValueNotifier(calendar);
    calendars.add(calendar);
  }
  final String initialBrand;
  late final IcsVisualCapture capture;
  final _Feed feed;
  final theme = ThemeProvider();
  final locale = LocaleProvider();
  final calendar = CalendarSyncProvider();
  final locations = LocationReminderProvider();
  final notifications = NotificationService();
  final calendars = <CalendarSyncProvider>[];
  final navigator = GlobalKey<NavigatorState>();
  final view = ValueNotifier(const _View(Size(390, 844), 1, 0));
  final existing = IcsSubscription(
    id: 'existing',
    name: 'Previously confirmed 用户订阅',
    url: 'https://feed.test/existing.ics',
    lastSyncedAt: DateTime.utc(2026, 11, 8),
  );
  late final _Store store;
  late final String originalRaw;
  late final String originalCache;
  late final ValueNotifier<CalendarSyncProvider> current;
  late final SharedPreferences prefs;
  late MaterialPageRoute<void> parentRoute;

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
    });
    await _frames(tester);
    await capturePhase(tester, 'live-presentation');
  }

  Future<void> capturePhase(WidgetTester tester, String phase) async {
    final metadata = (await tester.runAsync(
      () async => <String, Object?>{
        'memoryRows': current.value.subscriptions
            .map((row) => row.toJson())
            .toList(),
        'diskRows': await store.raw(_key),
        'diskExistingCache': await store.raw('duoyi_ics_events_existing'),
        'draftAttempts': store.draftAttempts,
        'httpRequests': feed.requests.map((uri) => uri.toString()).toList(),
        'isSyncing': current.value.isSyncing,
        'needsReconciliation': current.value.icsStorageNeedsReconciliation,
        'lifetime': current.value.icsLifetimeGeneration,
        'originProvider': identical(current.value, calendar)
            ? 'initial'
            : 'replacement',
        'parentCurrent': parentRoute.isCurrent,
        'results': current.value.icsRefreshResults.map(
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

  Future<void> invalidate(
    WidgetTester tester,
    _Invalidation invalidation,
    ModalRoute<dynamic> owned,
  ) async {
    switch (invalidation) {
      case _Invalidation.modal:
        navigator.currentState!.removeRoute(owned);
      case _Invalidation.back:
        await tester.binding.handlePopRoute();
        await _frames(tester);
        expect(
          owned.isCurrent,
          isFalse,
          reason: 'back revoked the owned modal',
        );
      case _Invalidation.parent:
        navigator.currentState!.removeRoute(parentRoute);
      case _Invalidation.account:
        AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      case _Invalidation.replacement:
        final replacement = (await tester.runAsync(
          () async => CalendarSyncProvider(),
        ))!;
        expect(
          replacement.icsLifetimeGeneration,
          calendar.icsLifetimeGeneration,
        );
        calendars.add(replacement);
        current.value = replacement;
      // Leave outgoing provider alive: identity, not disposal, must revoke it.
      case _Invalidation.lifetime:
        final generation = calendar.icsLifetimeGeneration;
        calendar.resetLocalState();
        expect(calendar.icsLifetimeGeneration, greaterThan(generation));
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

  Future<void> waitResult(
    WidgetTester tester,
    String id,
    IcsRefreshStatus status,
  ) async {
    await _until(
      tester,
      () =>
          current.value.icsRefreshResults[id]?.status == status &&
          !current.value.isSyncing,
      'owned $id ${status.name} result',
    );
    await drain(tester);
  }

  Future<void> expectBaseline() async {
    expect(await store.raw(_key), originalRaw);
    expect(await store.raw('duoyi_ics_events_existing'), originalCache);
    expect(prefs.getString(_key), originalRaw);
    await prefs.reload();
    expect(prefs.getString(_key), originalRaw);
  }

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
      await _frames(tester);
    } finally {
      for (final provider in calendars) {
        provider.dispose();
      }
      current.dispose();
      view.dispose();
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

class _Step {
  _Step(this.failure, {this.held = false});
  final _Failure failure;
  final bool held;
  final started = Completer<void>();
  final _released = Completer<void>();
  void release() {
    if (!_released.isCompleted) _released.complete();
  }
}

class _Store extends InMemorySharedPreferencesStore {
  _Store(String brand, String originalRaw, String originalCache)
    : super.withData({
        'flutter.duoyi_locale_v1': 'zh',
        'flutter.active_brand': brand,
        'flutter.theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
        'flutter.$_key': originalRaw,
        'flutter.duoyi_ics_events_existing': originalCache,
      });
  final snapshots = <List<Map<String, dynamic>>>[];
  final _steps = <_Step>[];
  final _all = <_Step>[];

  List<Map<String, dynamic>> get draftAttempts => snapshots
      .expand((rows) => rows)
      .where(
        (row) =>
            row['name'] == _literalName.trim() && row['lastSyncedAt'] == null,
      )
      .toList();

  void plan(List<_Step> steps) {
    _steps.addAll(steps);
    _all.addAll(steps);
  }

  _Step holdNext({_Failure failure = _Failure.none}) {
    final step = _Step(failure, held: true);
    plan([step]);
    return step;
  }

  void releaseAll() {
    for (final step in _all) {
      step.release();
    }
  }

  void clearUnusedSteps() => _steps.clear();
  Future<String?> raw(String key) async =>
      (await getAll())['flutter.$key'] as String?;

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key != 'flutter.$_key') return super.setValue(type, key, value);
    snapshots.add(_decodeRows(value as String));
    final step = _steps.isEmpty ? null : _steps.removeAt(0);
    if (step != null) {
      step.started.complete();
      if (step.held) await step._released.future;
      if (step.failure == _Failure.beforeFalse) return false;
    }
    final saved = await super.setValue(type, key, value);
    if (step?.failure == _Failure.writeThenFalse) return false;
    if (step?.failure == _Failure.writeThenThrow) {
      throw StateError('PRIVATE synthetic ICS persistence detail');
    }
    return saved;
  }
}

List<Map<String, dynamic>> _decodeRows(String? raw) =>
    (jsonDecode(raw ?? '[]') as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();

http.Response _response({int status = 200, String body = _emptyCalendar}) =>
    http.Response(
      body,
      status,
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
  final dialogWasCurrentAtDispatch = <bool>[];
  final _next = <_HttpGate>[];
  final _all = <_HttpGate>[];
  ModalRoute<dynamic>? dialogRoute;

  _HttpGate holdNext() {
    final gate = _HttpGate();
    _next.add(gate);
    _all.add(gate);
    return gate;
  }

  Future<http.Response> respond(http.Request request) async {
    requests.add(request.url);
    dialogWasCurrentAtDispatch.add(dialogRoute?.isCurrent ?? false);
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
