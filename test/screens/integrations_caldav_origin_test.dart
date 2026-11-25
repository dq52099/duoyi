import 'dart:async';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/notification_ui_copy.dart';
import 'package:duoyi/screens/integrations_screen.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/calendar_sync_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    I18n.setLocale(AppLocale.zh);
    SharedPreferences.setMockInitialValues({
      'duoyi_locale_v1': AppLocale.zh.storageValue,
    });
  });
  tearDown(() => I18n.setLocale(AppLocale.zh));

  for (final save in [false, true]) {
    for (final cancel in [false, true]) {
      testWidgets(
        '${save ? 'save' : 'remove'} ${cancel ? 'cancellation is silent' : 'failure uses live safe copy'}',
        (tester) async {
          final sync = _Sync()
            ..error = cancel
                ? const AccountPreferenceWriteCanceled()
                : StateError('PRIVATE storage error');
          await _mount(tester, sync);
          try {
            if (save) {
              await _openEdit(tester);
              await tester.tap(
                find.widgetWithText(
                  FilledButton,
                  NotificationUiCopy.saveAction,
                ),
              );
            } else {
              (await _remove(tester))();
            }
            await tester.pumpAndSettle();
            expect(sync.calls, 1);
            expect(tester.takeException(), isNull);
            expect(find.textContaining('PRIVATE storage error'), findsNothing);
            if (cancel) {
              expect(find.byType(SnackBar), findsNothing);
            } else {
              expect(find.text('日历配置保存失败，请重试。'), findsOneWidget);
              I18n.setLocale(AppLocale.en);
              await tester.pump();
              expect(
                find.text(
                  'Could not save the calendar configuration. Please try again.',
                ),
                findsOneWidget,
              );
            }
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            sync.dispose();
          }
        },
      );
    }
  }

  for (final invalidation in ['cleaner', 'target']) {
    testWidgets('retained remove rejects $invalidation change', (tester) async {
      final sync = _Sync();
      await _mount(tester, sync);
      try {
        final remove = await _remove(tester);
        if (invalidation == 'cleaner') {
          AccountLocalDataCleaner.invalidateInFlightAccountWrites();
        } else {
          sync.revision++;
        }
        remove();
        await tester.pumpAndSettle();
        expect(sync.calls, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        sync.dispose();
      }
    });
    testWidgets('open config dialog rejects $invalidation change before Save', (
      tester,
    ) async {
      final sync = _Sync();
      await _mount(tester, sync);
      try {
        await _openEdit(tester);
        if (invalidation == 'cleaner') {
          AccountLocalDataCleaner.invalidateInFlightAccountWrites();
        } else {
          sync.revision++;
        }
        await tester.tap(
          find.widgetWithText(FilledButton, NotificationUiCopy.saveAction),
        );
        await tester.pumpAndSettle();
        expect(sync.calls, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        sync.dispose();
      }
    });
  }

  testWidgets(
    'old failed save cannot show feedback after a newer target intent',
    (tester) async {
      final sync = _Sync();
      late Completer<void> held;
      await tester.runAsync(() async {
        held = Completer<void>();
      });
      sync.pending = held.future;
      await _mount(tester, sync);
      try {
        (await _remove(tester))();
        await tester.pump();
        sync.revision++;
        held.completeError(StateError('PRIVATE old storage failure'));
        await tester.runAsync(() async {
          await Future<void>.delayed(Duration.zero);
        });
        await tester.pumpAndSettle();
        expect(find.byType(SnackBar), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        sync.dispose();
      }
    },
  );
}

Future<void> _mount(WidgetTester tester, _Sync sync) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<CalendarSyncProvider>.value(
      value: sync,
      child: const MaterialApp(home: IntegrationsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _vertical() => find
    .byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
    )
    .first;
Future<VoidCallback> _remove(WidgetTester tester) async {
  final finder = find.widgetWithText(
    OutlinedButton,
    NotificationUiCopy.calDavRemove,
  );
  await tester.scrollUntilVisible(finder, 200, scrollable: _vertical());
  await tester.pumpAndSettle();
  return tester.widget<OutlinedButton>(finder).onPressed!;
}

Future<void> _openEdit(WidgetTester tester) async {
  final finder = find.widgetWithText(
    OutlinedButton,
    NotificationUiCopy.calDavEdit,
  );
  await tester.scrollUntilVisible(finder, 200, scrollable: _vertical());
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

class _Sync extends CalendarSyncProvider {
  Object? error;
  Future<void>? pending;
  int calls = 0;
  int revision = 1;
  @override
  int get writeTargetRevision => revision;
  @override
  CalDavWriteTarget? get writeTarget => const CalDavWriteTarget(
    collectionUrl: 'https://caldav.test/calendar/',
    authorizationHeader: 'Basic synthetic',
  );
  Future<void> _act() async {
    calls++;
    revision++;
    if (pending != null) await pending;
    if (error != null) throw error!;
  }

  @override
  Future<void> saveWriteTarget(CalDavWriteTarget target) => _act();
  @override
  Future<void> clearWriteTarget() => _act();
}
