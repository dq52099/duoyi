import 'dart:async';
import 'dart:io';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/widget_ui_copy.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/widget_screen.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/android_widget_manager.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:duoyi/services/home_widget_service.dart';
import 'package:duoyi/services/widget_display_mode_store.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  test('both retained app shells pass their visible tab to WidgetScreen', () {
    final source = File('lib/main.dart').readAsStringSync();
    expect(
      RegExp(
        r'_buildTab\(tab,\s*safeVisibleTabs,\s*safeIndex\)',
      ).allMatches(source),
      hasLength(2),
    );
    expect(
      source,
      matches(
        RegExp(
          r'5\s*=>\s*WidgetScreen\(\s*key:\s*widgetKey,\s*isActive:\s*tab\s*==\s*activeIndex,\s*activityRevision:\s*_widgetActivityRevision,?\s*\)',
        ),
      ),
    );
    expect(source, contains('set _currentIndex(int value)'));
    expect(source, contains('_currentIndexValue == 5 || value == 5'));
    expect(source, contains('_widgetActivityRevision.value++'));
    expect(source, contains('_widgetActivityRevision.dispose()'));
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.zh);
    AndroidWidgetManager.debugIsAndroidOverride = true;
  });

  tearDown(() {
    I18n.setLocale(AppLocale.zh);
    AndroidWidgetManager.debugIsAndroidOverride = null;
  });

  testWidgets(
    'secondary widget route retains category and scroll across locale',
    (tester) async {
      final f = _Fixture();
      await f.mount(tester, pushAsSecondaryRoute: true);
      await _selectCategory(tester, WidgetCategory.life);
      final screen = find.byType(WidgetScreen);
      final state = tester.state(screen);
      final list = find.descendant(of: screen, matching: find.byType(ListView));
      final scrollable = find
          .descendant(of: list, matching: find.byType(Scrollable))
          .first;
      await tester.drag(list, const Offset(0, -230));
      await tester.pumpAndSettle();
      var position = tester.state<ScrollableState>(scrollable).position;
      final offset = position.pixels;
      expect(offset, greaterThan(0));

      for (final locale in [AppLocale.en, AppLocale.zh]) {
        I18n.setLocale(locale);
        await tester.pumpAndSettle();
        expect(tester.state(screen), same(state));
        // Locale-sensitive scroll physics may replace ScrollPosition while
        // preserving the user's offset and the mounted page State.
        position = tester.state<ScrollableState>(scrollable).position;
        expect(position.pixels, closeTo(offset, 0.01));
        final filter = find.byWidgetPredicate(
          (w) => w is SegmentedButton<WidgetCategory>,
        );
        // The ListView may dispose its offscreen filter; reveal it without
        // changing the selected category before inspecting the control.
        await tester.scrollUntilVisible(filter, -200, scrollable: scrollable);
        await tester.pumpAndSettle();
        final category = tester.widget<SegmentedButton<WidgetCategory>>(filter);
        expect(category.selected, {WidgetCategory.life});
        expect(find.text(I18n.tr('nav.widget')), findsOneWidget);
        expect(tester.takeException(), isNull);
        position.jumpTo(offset);
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets(
    'secondary widget route keeps a pending pin locked across locale',
    (tester) async {
      final f = _Fixture();
      await f.mount(tester, pushAsSecondaryRoute: true);
      final state = tester.state(find.byType(WidgetScreen));
      f.channels.holdNextPinResult();
      await _tapAdd(tester, DuoyiWidgetKind.todo);
      await _waitFor(tester, f.channels.pinResultStarted!.future);
      final supportCalls = f.channels.supportCalls;

      I18n.setLocale(AppLocale.en);
      // A pending Add contains an indeterminate spinner, so pump fixed frames.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.state(find.byType(WidgetScreen)), same(state));
      expect(_addButton(tester, DuoyiWidgetKind.todo).onPressed, isNull);
      expect(find.text(WidgetUiCopy.requestingAdd), findsOneWidget);
      expect(f.channels.supportCalls, supportCalls);
      expect(f.channels.pinRequestCalls, 1);

      await _release(tester, f.channels.pinResultGate!, <String, Object>{
        'requestId': f.channels.pendingPinResultRequestId!,
        'status': 'confirmed',
        'kind': 'todo',
        'style': 'standard',
        'widgetId': 41,
      });
      expect(_addButton(tester, DuoyiWidgetKind.todo).onPressed, isNotNull);
      expect(
        find.text(
          WidgetUiCopy.pinSuccessSnackBar(WidgetDisplayMode.standard.label),
        ),
        findsOneWidget,
      );
      expect(f.channels.pinRequestCalls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final invalidation in [
    'session',
    'lock',
    'update',
    'covered',
    'inactive-tab',
  ]) {
    testWidgets('retained style selection rejects $invalidation', (
      tester,
    ) async {
      final store = _WidgetStyleStore();
      final f = _Fixture(styleStore: store);
      await f.mount(tester);
      final oldSelect = tester
          .widget<SegmentedButton<WidgetDisplayMode>>(
            find.byWidgetPredicate(
              (w) => w is SegmentedButton<WidgetDisplayMode>,
            ),
          )
          .onSelectionChanged!;
      if (invalidation == 'session') f.auth.switchAccount();
      if (invalidation == 'lock') f.lock.setLocked(true);
      if (invalidation == 'update') f.updater.setMustUpdate(true);
      if (invalidation == 'covered') {
        await f.cover(tester, label: 'Covering style');
      }
      if (invalidation == 'inactive-tab') {
        await f.mount(tester, isActive: false);
      }
      oldSelect({WidgetDisplayMode.detailed});
      await tester.pumpAndSettle();
      expect(store.modeWrites, 0);
      expect(tester.takeException(), isNull);
    });
  }

  for (final succeeds in [false, true]) {
    testWidgets(
      'held style save=$succeeds cannot replace another tab message',
      (tester) async {
        final store = _WidgetStyleStore();
        final f = _Fixture(styleStore: store);
        await f.mount(tester);
        final select = tester
            .widget<SegmentedButton<WidgetDisplayMode>>(
              find.byWidgetPredicate(
                (w) => w is SegmentedButton<WidgetDisplayMode>,
              ),
            )
            .onSelectionChanged!;
        await tester.runAsync(() async {
          store.holdModeWrite();
          select({WidgetDisplayMode.detailed});
          await store.started!.future.timeout(const Duration(seconds: 3));
        });
        await f.mount(tester, isActive: false);
        f.scaffoldMessengerKey.currentState!.showSnackBar(
          const SnackBar(content: Text('Current tab feedback')),
        );
        await tester.pump();
        await tester.runAsync(() async {
          store.release!.complete(succeeds);
          await AccountPreferenceWrites.drain();
        });
        await tester.pumpAndSettle();
        expect(find.text('Current tab feedback'), findsOneWidget);
        expect(find.text(WidgetUiCopy.styleSyncFailed), findsNothing);
        expect(tester.takeException(), isNull);
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getString('duoyi_widget_display_mode'),
          succeeds ? 'detailed' : isNull,
        );
      },
    );
  }

  for (final succeeds in [false, true]) {
    testWidgets(
      'held style save=$succeeds blocks stale Add and uses the settled style',
      (tester) async {
        final store = _WidgetStyleStore();
        final f = _Fixture(styleStore: store);
        await f.mount(tester, viewport: const Size(390, 2400));

        final todo = find.byKey(const ValueKey(DuoyiWidgetKind.todo));
        final oldAdd = _addButton(tester, DuoyiWidgetKind.todo).onPressed!;
        final supportCallsBefore = f.channels.supportCalls;
        final selector = _styleSelector(tester);

        await tester.runAsync(() async {
          store.holdModeWrite();
          selector.onSelectionChanged!({WidgetDisplayMode.detailed});
          await store.started!.future.timeout(const Duration(seconds: 3));
        });
        await tester.pump();

        expect(_styleSelector(tester).onSelectionChanged, isNull);
        expect(_addButton(tester, DuoyiWidgetKind.todo).onPressed, isNull);
        expect(
          find.descendant(
            of: todo,
            matching: find.text(WidgetUiCopy.updatingStyle),
          ),
          findsOneWidget,
        );
        oldAdd();
        await tester.pump();
        expect(f.channels.supportCalls, supportCallsBefore);
        expect(f.channels.pinRequestCalls, 0);

        await tester.runAsync(() async {
          store.release!.complete(succeeds);
          await AccountPreferenceWrites.drain();
        });
        await tester.pumpAndSettle();

        final settledMode = succeeds
            ? WidgetDisplayMode.detailed
            : WidgetDisplayMode.standard;
        await _waitForStyleChange(tester, settledMode);
        expect(_styleSelector(tester).selected, {settledMode});
        expect(_addButton(tester, DuoyiWidgetKind.todo).onPressed, isNotNull);

        f.channels.nextPinRequestStatus = 'unsupported_launcher';
        await _tapAdd(tester, DuoyiWidgetKind.todo);
        await tester.pumpAndSettle();
        expect(f.channels.pinRequestCalls, 1);
        expect(f.channels.pinRequestStyles, [settledMode.id]);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'changing style while pin support is held cancels the stale pin request',
    (tester) async {
      final store = _WidgetStyleStore();
      final f = _Fixture(styleStore: store);
      await f.mount(tester, viewport: const Size(390, 2400));
      f.channels.holdNextSupportCheck();

      await _tapVisibleAdd(tester, DuoyiWidgetKind.todo);
      await _waitFor(tester, f.channels.supportCheckStarted!.future);
      expect(f.channels.pinRequestCalls, 0);

      final select = _styleSelector(tester).onSelectionChanged!;
      await tester.runAsync(() async {
        select({WidgetDisplayMode.detailed});
        await AccountPreferenceWrites.drain();
      });
      await _waitForStyleChange(tester, WidgetDisplayMode.detailed);
      expect(store.modeWrites, 1);

      await _release(tester, f.channels.supportCheckGate!, true);
      expect(f.channels.pinRequestCalls, 0);
      expect(_addButton(tester, DuoyiWidgetKind.todo).onPressed, isNotNull);

      f.channels.nextPinRequestStatus = 'unsupported_launcher';
      await _tapAdd(tester, DuoyiWidgetKind.todo);
      await tester.pumpAndSettle();
      expect(f.channels.pinRequestCalls, 1);
      expect(f.channels.pinRequestStyles, ['detailed']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'changing style during held pin confirmation does not resend the pin',
    (tester) async {
      final store = _WidgetStyleStore();
      final f = _Fixture(styleStore: store);
      await f.mount(tester, viewport: const Size(390, 2400));
      f.channels.holdNextPinResult();

      await _tapVisibleAdd(tester, DuoyiWidgetKind.todo);
      await _waitFor(tester, f.channels.pinResultStarted!.future);
      expect(f.channels.pinRequestCalls, 1);
      expect(f.channels.pinRequestStyles, ['standard']);

      final select = _styleSelector(tester).onSelectionChanged!;
      await tester.runAsync(() async {
        select({WidgetDisplayMode.detailed});
        await AccountPreferenceWrites.drain();
      });
      await _waitForStyleChange(tester, WidgetDisplayMode.detailed);
      expect(store.modeWrites, 1);
      expect(f.channels.pinRequestCalls, 1);

      await _release(tester, f.channels.pinResultGate!, <String, Object>{
        'requestId': f.channels.pendingPinResultRequestId!,
        'status': 'confirmed',
        'kind': 'todo',
        'style': 'standard',
        'widgetId': 41,
      });

      expect(f.channels.pinRequestCalls, 1);
      expect(f.channels.pinRequestStyles, ['standard']);
      expect(_styleSelector(tester).selected, {WidgetDisplayMode.detailed});
      expect(
        find.text(
          WidgetUiCopy.pinSuccessSnackBar(WidgetDisplayMode.standard.label),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'held initial style read blocks Add and pins with the loaded style',
    (tester) async {
      final store = _WidgetStyleStore();
      await tester.runAsync(() async => store.holdNextGetAll());
      final f = _Fixture(styleStore: store, loadThemeFromStorage: false);
      await f.mount(tester, settle: false);
      await _waitFor(tester, store.getAllStarted!.future);

      expect(_addButton(tester, DuoyiWidgetKind.todo).onPressed, isNull);
      expect(f.channels.pinRequestCalls, 0);

      await tester.runAsync(() async {
        store.getAllRelease!.complete({
          'flutter.duoyi_widget_display_mode': 'detailed',
        });
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpAndSettle();

      expect(_styleSelector(tester).selected, {WidgetDisplayMode.detailed});
      expect(_addButton(tester, DuoyiWidgetKind.todo).onPressed, isNotNull);
      f.channels.nextPinRequestStatus = 'unsupported_launcher';
      await _tapAdd(tester, DuoyiWidgetKind.todo);
      await tester.pumpAndSettle();
      expect(f.channels.pinRequestCalls, 1);
      expect(f.channels.pinRequestStyles, ['detailed']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed initial style read retries and restores Add with saved style',
    (tester) async {
      final store = _WidgetStyleStore(
        initialValues: {'flutter.duoyi_widget_display_mode': 'detailed'},
      );
      await tester.runAsync(() async => store.holdNextGetAll());
      final f = _Fixture(styleStore: store, loadThemeFromStorage: false);
      await f.mount(tester, settle: false);
      await _waitFor(tester, store.getAllStarted!.future);

      await tester.runAsync(() async {
        store.getAllRelease!.completeError(StateError('held read failed'));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpAndSettle();

      expect(find.text(WidgetUiCopy.styleLoadFailed), findsWidgets);
      expect(_addButton(tester, DuoyiWidgetKind.todo).onPressed, isNull);
      expect(f.channels.pinRequestCalls, 0);
      final oldRetry = tester
          .widget<TextButton>(
            find.byKey(const ValueKey('widget_style_load_retry')),
          )
          .onPressed!;
      oldRetry();
      await tester.pumpAndSettle();

      expect(_styleSelector(tester).selected, {WidgetDisplayMode.detailed});
      expect(find.text(WidgetUiCopy.styleLoadFailed), findsNothing);
      expect(_addButton(tester, DuoyiWidgetKind.todo).onPressed, isNotNull);
      final readsAfterSuccess = store.getAllCalls;
      oldRetry();
      await tester.pumpAndSettle();
      expect(store.getAllCalls, readsAfterSuccess);
      expect(_styleSelector(tester).selected, {WidgetDisplayMode.detailed});

      f.channels.nextPinRequestStatus = 'unsupported_launcher';
      await _tapAdd(tester, DuoyiWidgetKind.todo);
      await tester.pumpAndSettle();
      expect(f.channels.pinRequestCalls, 1);
      expect(f.channels.pinRequestStyles, ['detailed']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('same-frame retained Add rejects a new style selection', (
    tester,
  ) async {
    final store = _WidgetStyleStore();
    final f = _Fixture(styleStore: store);
    await f.mount(tester);
    final oldAdd = _addButton(tester, DuoyiWidgetKind.todo).onPressed!;
    final supportBefore = f.channels.supportCalls;
    store.holdModeWrite();
    _styleSelector(tester).onSelectionChanged!({WidgetDisplayMode.detailed});
    // No frame is pumped between selecting a style and invoking the old Add.
    oldAdd();
    expect(f.channels.supportCalls, supportBefore);
    expect(f.channels.pinRequestCalls, 0);
    await _waitFor(tester, store.started!.future);
    await tester.runAsync(() async {
      store.release!.complete(true);
      await AccountPreferenceWrites.drain();
    });
    await _waitForStyleChange(tester, WidgetDisplayMode.detailed);
    f.channels.nextPinRequestStatus = 'unsupported_launcher';
    await _tapAdd(tester, DuoyiWidgetKind.todo);
    await tester.pumpAndSettle();
    expect(f.channels.pinRequestStyles, ['detailed']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('A to B to A invalidates the held Add preflight', (tester) async {
    final f = _Fixture(styleStore: _WidgetStyleStore());
    await f.mount(tester, viewport: const Size(390, 2400));
    f.channels.holdNextSupportCheck();
    await _tapVisibleAdd(tester, DuoyiWidgetKind.todo);
    await _waitFor(tester, f.channels.supportCheckStarted!.future);
    for (final mode in [
      WidgetDisplayMode.detailed,
      WidgetDisplayMode.standard,
    ]) {
      await tester.runAsync(() async {
        _styleSelector(tester).onSelectionChanged!({mode});
        await AccountPreferenceWrites.drain();
      });
      await _waitForStyleChange(tester, mode);
    }
    await _release(tester, f.channels.supportCheckGate!, true);
    expect(f.channels.pinRequestCalls, 0);
    f.channels.nextPinRequestStatus = 'unsupported_launcher';
    await _tapAdd(tester, DuoyiWidgetKind.todo);
    await tester.pumpAndSettle();
    expect(f.channels.pinRequestStyles, ['standard']);
    expect(tester.takeException(), isNull);
  });

  for (final succeeds in [false, true]) {
    testWidgets('held native style save=$succeeds keeps Add disabled', (
      tester,
    ) async {
      final store = _WidgetStyleStore();
      final f = _Fixture(styleStore: store);
      await f.mount(tester, viewport: const Size(390, 2400));
      late Completer<void> entered;
      late Completer<bool> release;
      await tester.runAsync(() async {
        entered = Completer<void>();
        release = Completer<bool>();
      });
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('home_widget');
      var hold = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        final args = call.arguments as Map?;
        if (call.method == 'saveWidgetData' &&
            args?['id'] == 'widget_display_mode' &&
            hold) {
          hold = false;
          entered.complete();
          return release.future;
        }
        if (call.method == 'getWidgetData') return null;
        return true;
      });
      HomeWidgetService.supportedForTesting = true;
      addTearDown(() async {
        if (!release.isCompleted) release.complete(false);
        await AccountPreferenceWrites.drain();
        HomeWidgetService.supportedForTesting = null;
        messenger.setMockMethodCallHandler(channel, null);
      });
      await tester.runAsync(() async {
        HomeWidgetService.resetAccountCache();
        expect(await HomeWidgetService.waitForAccountClear(), isTrue);
      });
      hold = true;
      final oldAdd = _addButton(tester, DuoyiWidgetKind.todo).onPressed!;
      final supportBefore = f.channels.supportCalls;
      await tester.runAsync(() async {
        _styleSelector(tester).onSelectionChanged!({
          WidgetDisplayMode.detailed,
        });
        await entered.future.timeout(const Duration(seconds: 3));
      });
      await tester.pump();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('duoyi_widget_display_mode'), 'detailed');
      expect(_addButton(tester, DuoyiWidgetKind.todo).onPressed, isNull);
      oldAdd();
      expect(f.channels.supportCalls, supportBefore);
      expect(f.channels.pinRequestCalls, 0);
      await tester.runAsync(() async {
        release.complete(succeeds);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await _waitForStyleChange(tester, WidgetDisplayMode.detailed);
      expect(_addButton(tester, DuoyiWidgetKind.todo).onPressed, isNotNull);
      expect(
        find.text(WidgetUiCopy.styleSyncFailed),
        succeeds ? findsNothing : findsOneWidget,
      );
      f.channels.nextPinRequestStatus = 'unsupported_launcher';
      await _tapAdd(tester, DuoyiWidgetKind.todo);
      await tester.pumpAndSettle();
      expect(f.channels.pinRequestStyles, ['detailed']);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'retained style selection stays invalid after returning to the tab',
    (tester) async {
      final store = _WidgetStyleStore();
      final f = _Fixture(styleStore: store);
      await f.mount(tester);
      final oldSelect = tester
          .widget<SegmentedButton<WidgetDisplayMode>>(
            find.byWidgetPredicate(
              (w) => w is SegmentedButton<WidgetDisplayMode>,
            ),
          )
          .onSelectionChanged!;
      await f.mount(tester, isActive: false);
      await f.mount(tester);
      oldSelect({WidgetDisplayMode.detailed});
      await tester.pumpAndSettle();
      expect(store.modeWrites, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('held pin support stays invalid after returning to the tab', (
    tester,
  ) async {
    final f = _Fixture();
    await f.mount(tester);
    f.channels.holdNextSupportCheck();
    await _tapAdd(tester, DuoyiWidgetKind.todo);
    await _waitFor(tester, f.channels.supportCheckStarted!.future);
    await f.mount(tester, isActive: false, settle: false);
    await f.mount(tester, settle: false);
    await _release(tester, f.channels.supportCheckGate!, true);
    expect(f.channels.pinRequestCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('same-frame activity revisions invalidate old style callbacks', (
    tester,
  ) async {
    final store = _WidgetStyleStore();
    final f = _Fixture(styleStore: store);
    await f.mount(tester);
    final oldSelect = tester
        .widget<SegmentedButton<WidgetDisplayMode>>(
          find.byWidgetPredicate(
            (w) => w is SegmentedButton<WidgetDisplayMode>,
          ),
        )
        .onSelectionChanged!;
    f.activityRevision.value++;
    f.activityRevision.value++;
    oldSelect({WidgetDisplayMode.detailed});
    await tester.pumpAndSettle();
    expect(store.modeWrites, 0);
    await f.mount(tester);
    tester
        .widget<SegmentedButton<WidgetDisplayMode>>(
          find.byWidgetPredicate(
            (w) => w is SegmentedButton<WidgetDisplayMode>,
          ),
        )
        .onSelectionChanged!({WidgetDisplayMode.detailed});
    await tester.pumpAndSettle();
    expect(store.modeWrites, 1);
    expect(tester.takeException(), isNull);
  });

  for (final roundtrip in ['tab', 'same-frame']) {
    testWidgets(
      'held dashboard refresh stays invalid after $roundtrip return',
      (tester) async {
        final f = _Fixture();
        await f.mount(tester);
        final oldSupported = HomeWidgetService.supportedForTesting;
        final oldRefresher = HomeWidgetService.dashboardDataRefresher;
        HomeWidgetService.supportedForTesting = true;
        final gate = Completer<bool>();
        var calls = 0;
        HomeWidgetService.dashboardDataRefresher = () {
          calls++;
          return calls == 1 ? gate.future : Future.value(true);
        };
        addTearDown(() {
          if (!gate.isCompleted) gate.complete(false);
          HomeWidgetService.supportedForTesting = oldSupported;
          HomeWidgetService.dashboardDataRefresher = oldRefresher;
        });
        final refresh = find.widgetWithIcon(IconButton, Icons.refresh).first;
        final oldRefresh = tester.widget<IconButton>(refresh).onPressed!;
        oldRefresh();
        await tester.pump();
        if (roundtrip == 'tab') {
          await f.mount(tester, isActive: false);
          await f.mount(tester);
        } else {
          f.activityRevision.value++;
          f.activityRevision.value++;
          await f.mount(tester);
        }
        oldRefresh();
        expect(calls, 1);
        expect(tester.widget<IconButton>(refresh).onPressed, isNull);
        gate.complete(true);
        await tester.pumpAndSettle();
        expect(find.text(WidgetUiCopy.refreshSuccess), findsNothing);
        oldRefresh();
        expect(calls, 1);
        tester.widget<IconButton>(refresh).onPressed!();
        await tester.pumpAndSettle();
        expect(calls, 2);
        expect(find.text(WidgetUiCopy.refreshSuccess), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'style canceled by an active preference boundary restores saved mode',
    (tester) async {
      final store = _WidgetStyleStore(
        initialValues: {'flutter.duoyi_widget_display_mode': 'standard'},
      );
      final f = _Fixture(styleStore: store);
      await f.mount(tester, viewport: const Size(390, 2400));
      final release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      final boundary = AccountPreferenceWrites.boundary(() => release.future);
      expect(AccountPreferenceWrites.isBoundaryActive, isTrue);
      _styleSelector(tester).onSelectionChanged!({WidgetDisplayMode.detailed});
      await tester.pump();
      expect(_styleSelector(tester).selected, {WidgetDisplayMode.detailed});
      expect(_addButton(tester, DuoyiWidgetKind.todo).onPressed, isNull);
      expect(store.modeWrites, 0);
      release.complete();
      await boundary;
      await _waitForStyleChange(tester, WidgetDisplayMode.standard);
      expect(store.modeWrites, 0);
      expect(_addButton(tester, DuoyiWidgetKind.todo).onPressed, isNotNull);
      expect(
        find.byKey(const ValueKey('widget_style_sync_pending')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('pending style refresh cancels unsent same-style pin preflight', (
    tester,
  ) async {
    const intent = WidgetDisplayModeSelection(
      mode: 'detailed',
      intentId: 'pending-detail',
      pending: true,
    );
    final f = _Fixture(
      styleStore: _WidgetStyleStore(
        initialValues: {
          'flutter.duoyi_widget_display_mode': 'detailed',
          'flutter.${WidgetDisplayModeSelection.storageKey}': intent.encode(),
        },
      ),
    );
    await f.mount(tester, viewport: const Size(390, 2400));
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final nativeGate = Completer<bool>();
    var nativeStarted = false;
    const channel = MethodChannel('home_widget');
    messenger.setMockMethodCallHandler(channel, (call) async {
      final args = call.arguments as Map?;
      if (call.method == 'saveWidgetData' &&
          args?['id'] == 'widget_display_mode') {
        nativeStarted = true;
        return nativeGate.future;
      }
      if (call.method == 'getWidgetData') return null;
      return true;
    });
    final oldSupported = HomeWidgetService.supportedForTesting;
    final oldRefresher = HomeWidgetService.dashboardDataRefresher;
    HomeWidgetService.supportedForTesting = true;
    HomeWidgetService.dashboardDataRefresher = () async => true;
    addTearDown(() {
      if (!nativeGate.isCompleted) nativeGate.complete(false);
      HomeWidgetService.supportedForTesting = oldSupported;
      HomeWidgetService.dashboardDataRefresher = oldRefresher;
      messenger.setMockMethodCallHandler(channel, null);
    });
    f.channels.holdNextSupportCheck();
    await _tapVisibleAdd(tester, DuoyiWidgetKind.todo);
    expect(f.channels.supportCheckStarted!.isCompleted, isTrue);
    final refresh = tester
        .widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.refresh).first,
        )
        .onPressed!;
    refresh();
    for (var i = 0; i < 20 && !nativeStarted; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    expect(nativeStarted, isTrue);
    expect(_addButton(tester, DuoyiWidgetKind.todo).onPressed, isNull);
    await _release(tester, f.channels.supportCheckGate!, true);
    expect(f.channels.pinRequestCalls, 0);
    await tester.runAsync(() async {
      nativeGate.complete(true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
    expect(f.channels.pinRequestCalls, 0);
    expect(
      find.byKey(const ValueKey('widget_style_sync_pending')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'issued pin stays pending and acknowledges receipt after return',
    (tester) async {
      final f = _Fixture();
      await f.mount(tester);
      f.channels.holdNextPinResult();
      await _tapAdd(tester, DuoyiWidgetKind.todo);
      await _waitFor(tester, f.channels.pinResultStarted!.future);
      expect(f.channels.pinRequestCalls, 1);
      f.activityRevision.value++;
      f.activityRevision.value++;
      await f.mount(tester, settle: false);
      await _tapAdd(tester, DuoyiWidgetKind.todo, settle: false);
      expect(f.channels.pinRequestCalls, 1);
      await _release(tester, f.channels.pinResultGate!, <String, Object>{
        'requestId': f.channels.pendingPinResultRequestId!,
        'status': 'confirmed',
        'kind': 'todo',
        'style': 'standard',
        'widgetId': 41,
      });
      expect(f.channels.methodCalls, contains('clearPinResult'));
      expect(f.channels.pinWaitCalls, contains('endWait'));
      expect(
        find.text(
          WidgetUiCopy.pinSuccessSnackBar(WidgetDisplayMode.standard.label),
        ),
        findsNothing,
      );
      f.channels.nextPinRequestStatus = 'failed';
      await _tapAdd(tester, DuoyiWidgetKind.todo);
      await tester.pumpAndSettle();
      expect(f.channels.pinRequestCalls, 2);
      expect(find.byType(AppDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('rechecking support allows only one pending native check', (
    tester,
  ) async {
    final f = _Fixture();
    await f.mount(tester);
    final initialCalls = f.channels.supportCalls;
    final recheck = tester
        .widget<TextButton>(
          find.widgetWithText(TextButton, WidgetUiCopy.actionRecheck),
        )
        .onPressed!;
    f.channels.holdNextSupportCheck();
    recheck();
    recheck();
    await _waitFor(tester, f.channels.supportCheckStarted!.future);
    expect(f.channels.supportCalls, initialCalls + 1);
    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, WidgetUiCopy.actionRecheck),
          )
          .onPressed,
      isNull,
    );
    await _release(tester, f.channels.supportCheckGate!, true);
    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, WidgetUiCopy.actionRecheck),
          )
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('held dashboard refresh preserves a covering route feedback', (
    tester,
  ) async {
    final f = _Fixture();
    await f.mount(tester);
    final oldSupported = HomeWidgetService.supportedForTesting;
    final oldRefresher = HomeWidgetService.dashboardDataRefresher;
    HomeWidgetService.supportedForTesting = true;
    final gate = Completer<bool>();
    var calls = 0;
    HomeWidgetService.dashboardDataRefresher = () {
      calls++;
      return gate.future;
    };
    addTearDown(() {
      if (!gate.isCompleted) gate.complete(false);
      HomeWidgetService.supportedForTesting = oldSupported;
      HomeWidgetService.dashboardDataRefresher = oldRefresher;
    });
    final refresh = find.widgetWithIcon(IconButton, Icons.refresh).first;
    final oldRefresh = tester.widget<IconButton>(refresh).onPressed!;
    oldRefresh();
    await tester.pump();
    expect(calls, 1);
    await f.cover(tester, label: 'New dashboard route');
    f.scaffoldMessengerKey.currentState!.showSnackBar(
      const SnackBar(content: Text('Dashboard route feedback')),
    );
    gate.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('Dashboard route feedback'), findsOneWidget);
    expect(find.text(WidgetUiCopy.refreshSuccess), findsNothing);
    oldRefresh();
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });

  for (final invalidation in [
    'account',
    'session',
    'lock',
    'update',
    'covered',
    'inactive-tab',
  ]) {
    testWidgets(
      'a stale pin support check cannot request a widget after $invalidation',
      (tester) async {
        final f = _Fixture();
        await f.mount(tester);
        f.channels.holdNextSupportCheck();

        await _tapAdd(tester, DuoyiWidgetKind.todo);
        await _waitFor(tester, f.channels.supportCheckStarted!.future);

        switch (invalidation) {
          case 'account':
            f.auth.switchAccount();
            AccountLocalDataCleaner.invalidateInFlightAccountWrites();
            break;
          case 'session':
            f.auth.switchAccount();
            break;
          case 'lock':
            f.lock.setLocked(true);
            break;
          case 'update':
            f.updater.setMustUpdate(true);
            break;
          case 'covered':
            await f.cover(
              tester,
              label: 'Covered pin support route',
              settle: false,
            );
            break;
          case 'inactive-tab':
            await f.mount(tester, isActive: false, settle: false);
            break;
        }

        await _release(tester, f.channels.supportCheckGate!, true);

        expect(f.channels.pinRequestCalls, 0);
        if (invalidation == 'covered') {
          expect(find.text('Covered pin support route'), findsOneWidget);
        }
        expect(find.byType(AppDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('a late pin result cannot present help on another retained tab', (
    tester,
  ) async {
    final f = _Fixture();
    await f.mount(tester);
    f.channels.holdNextPinResult();
    await _tapAdd(tester, DuoyiWidgetKind.todo);
    await _waitFor(tester, f.channels.pinResultStarted!.future);
    await f.mount(tester, isActive: false, settle: false);
    f.scaffoldMessengerKey.currentState!.removeCurrentSnackBar();
    await tester.pump();
    f.scaffoldMessengerKey.currentState!.showSnackBar(
      const SnackBar(content: Text('Other tab message')),
    );
    await tester.pump();
    await _release(tester, f.channels.pinResultGate!, <String, Object>{
      'requestId': f.channels.pendingPinResultRequestId!,
      'status': 'invalid_widget_id',
    });
    expect(find.text('Other retained tab'), findsOneWidget);
    expect(find.text('Other tab message'), findsOneWidget);
    expect(find.byType(AppDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final invalidation in ['account', 'covered', 'host', 'inactive-tab']) {
    testWidgets('retained banner settings rejects $invalidation', (
      tester,
    ) async {
      final f = _Fixture();
      await f.mount(tester);
      final button = find.widgetWithText(
        TextButton,
        WidgetUiCopy.actionAppSettings,
      );
      await tester.ensureVisible(button);
      final oldSettings = tester.widget<TextButton>(button).onPressed!;
      if (invalidation == 'account') {
        f.auth.switchAccount();
      } else if (invalidation == 'covered') {
        await f.cover(tester, label: 'Covering banner settings');
      } else if (invalidation == 'inactive-tab') {
        await f.mount(tester, isActive: false);
      } else {
        await f.mount(tester, hostPlatform: WidgetHostPlatform.ios);
        await f.mount(tester);
      }
      oldSettings();
      await tester.pumpAndSettle();
      expect(f.channels.openSettingsCalls, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'a failed pin result after cover preserves the covering route SnackBar',
    (tester) async {
      final f = _Fixture();
      await f.mount(tester);
      f.channels.holdNextPinResult();

      await _tapAdd(tester, DuoyiWidgetKind.todo);
      await _waitFor(tester, f.channels.pinResultStarted!.future);

      f.scaffoldMessengerKey.currentState!.removeCurrentSnackBar();
      await tester.pump();
      await f.cover(
        tester,
        label: 'Covering route with its own message',
        settle: false,
      );
      f.scaffoldMessengerKey.currentState!.showSnackBar(
        const SnackBar(
          content: Text('Covering route SnackBar'),
          duration: Duration(seconds: 20),
        ),
      );
      await tester.pump();

      final requestId = f.channels.pendingPinResultRequestId!;
      await _release(tester, f.channels.pinResultGate!, <String, Object>{
        'requestId': requestId,
        'status': 'invalid_widget_id',
        'kind': 'todo',
        'style': 'standard',
      });

      expect(find.text('Covering route SnackBar'), findsOneWidget);
      expect(find.byType(AppDialog), findsNothing);
      expect(find.text('Covering route with its own message'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final invalidation in [
    'covered',
    'account',
    'account-data',
    'lock',
    'update',
  ]) {
    testWidgets('retained pin help closes safely after $invalidation', (
      tester,
    ) async {
      final f = _Fixture();
      await f.mount(tester);
      f.channels.supportReplies.add(false);
      await _tapAdd(tester, DuoyiWidgetKind.todo);
      await tester.pumpAndSettle();

      expect(find.byType(AppDialog), findsOneWidget);
      final dismissFinder = find.ancestor(
        of: find.text(WidgetUiCopy.actionGotIt),
        matching: find.byType(FilledButton),
      );
      final settingsFinder = find.ancestor(
        of: find.text(WidgetUiCopy.actionOpenPermissions),
        matching: find.byType(TextButton),
      );
      final dismiss = tester
          .widget<FilledButton>(dismissFinder.first)
          .onPressed!;
      final openSettings = tester
          .widget<TextButton>(settingsFinder.first)
          .onPressed!;

      if (invalidation == 'covered') {
        await f.cover(tester, label: 'Newer route after retained help');
      } else if (invalidation == 'account') {
        f.auth.switchAccount();
      } else if (invalidation == 'account-data') {
        AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      } else if (invalidation == 'lock') {
        f.lock.setLocked(true);
      } else if (invalidation == 'update') {
        f.updater.setMustUpdate(true);
      }
      await tester.pump();

      openSettings();
      await tester.pumpAndSettle();
      expect(f.channels.openSettingsCalls, 0);

      if (invalidation == 'covered') {
        dismiss();
        await tester.pumpAndSettle();
        expect(find.text('Newer route after retained help'), findsOneWidget);
      } else {
        expect(find.byType(AppDialog), findsOneWidget);
        await tester.tap(find.text(WidgetUiCopy.actionGotIt));
        await tester.pumpAndSettle();
        expect(find.byType(AppDialog), findsNothing);

        await f.cover(tester, label: 'Newer route after dismissed help');
        dismiss();
        openSettings();
        await tester.pumpAndSettle();
        expect(find.text('Newer route after dismissed help'), findsOneWidget);
      }
      expect(f.channels.openSettingsCalls, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('current pin help can open system settings and close itself', (
    tester,
  ) async {
    final f = _Fixture();
    await f.mount(tester);
    f.channels.supportReplies.add(false);
    await _tapAdd(tester, DuoyiWidgetKind.todo);
    await tester.pumpAndSettle();
    await tester.tap(find.text(WidgetUiCopy.actionOpenPermissions));
    await tester.pumpAndSettle();
    expect(f.channels.openSettingsCalls, 1);
    expect(find.byType(AppDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'switching categories keeps the same kind pinned request pending',
    (tester) async {
      final f = _Fixture();
      await f.mount(tester);
      f.channels.holdNextPinResult();

      await _tapAdd(tester, DuoyiWidgetKind.todo);
      await _waitFor(tester, f.channels.pinResultStarted!.future);
      expect(f.channels.pinRequestCalls, 1);

      await _selectCategory(tester, WidgetCategory.life, settle: false);
      expect(find.byKey(const ValueKey(DuoyiWidgetKind.todo)), findsNothing);
      await _selectCategory(tester, WidgetCategory.all, settle: false);
      await _tapAdd(tester, DuoyiWidgetKind.todo, settle: false);

      expect(f.channels.pinRequestCalls, 1);
      await _release(tester, f.channels.pinResultGate!, <String, Object>{
        'requestId': f.channels.pendingPinResultRequestId!,
        'status': 'confirmed',
        'kind': 'todo',
        'style': 'standard',
        'widgetId': 41,
      });
      expect(tester.takeException(), isNull);
    },
  );

  for (final host in [WidgetHostPlatform.ios, WidgetHostPlatform.web]) {
    testWidgets(
      'stale Android support does not enable Android actions after switching to ${host.name}',
      (tester) async {
        final f = _Fixture();
        f.channels.holdNextSupportCheck();
        await f.mount(
          tester,
          hostPlatform: WidgetHostPlatform.android,
          settle: false,
        );
        await _waitFor(tester, f.channels.supportCheckStarted!.future);

        await f.mount(tester, hostPlatform: host, settle: false);
        await tester.pump();
        final label = WidgetUiCopy.hostAddAction(host);
        final todo = find.byKey(const ValueKey(DuoyiWidgetKind.todo));
        expect(
          find.descendant(
            of: todo,
            matching: find.widgetWithText(FilledButton, label),
          ),
          findsOneWidget,
        );

        await _release(tester, f.channels.supportCheckGate!, true);
        await tester.pumpAndSettle();
        await _tapAdd(tester, DuoyiWidgetKind.todo);
        await tester.pumpAndSettle();

        expect(f.channels.supportCalls, 1);
        expect(f.channels.canOpenSettingsCalls, 0);
        expect(f.channels.pinRequestCalls, 0);
        expect(f.channels.methodCalls, ['canRequestPinWidget']);
        expect(find.text(WidgetUiCopy.hostHelpMessage(host)), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('switching iOS to Android reloads support and permits pinning', (
    tester,
  ) async {
    final f = _Fixture();
    await f.mount(tester, hostPlatform: WidgetHostPlatform.ios);
    expect(f.channels.supportCalls, 0);

    f.channels.holdNextSupportCheck();
    await f.mount(
      tester,
      hostPlatform: WidgetHostPlatform.android,
      settle: false,
    );
    await _waitFor(tester, f.channels.supportCheckStarted!.future);
    expect(f.channels.supportCalls, 1);

    await _release(tester, f.channels.supportCheckGate!, true);
    await tester.pumpAndSettle();
    f.channels.nextPinRequestStatus = 'unsupported_launcher';
    await _tapAdd(tester, DuoyiWidgetKind.todo);
    await tester.pumpAndSettle();

    expect(f.channels.supportCalls, 2);
    expect(f.channels.canOpenSettingsCalls, 1);
    expect(f.channels.pinRequestCalls, 1);
    expect(find.byType(AppDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

// These preflight tests keep both controls mounted to isolate revision checks
// from list disposal. Avoid scrollUntilVisible, which aligns Add at the top.
Future<void> _tapVisibleAdd(WidgetTester tester, DuoyiWidgetKind kind) async {
  final button = find.descendant(
    of: find.byKey(ValueKey(kind)),
    matching: find.byType(FilledButton),
  );
  expect(button.hitTestable(), findsOneWidget);
  await tester.tap(button);
  await tester.pump();
}

Future<void> _tapAdd(
  WidgetTester tester,
  DuoyiWidgetKind kind, {
  bool settle = true,
}) async {
  final tile = find.byKey(ValueKey(kind));
  final scrollable = find
      .descendant(
        of: find.byType(ListView).first,
        matching: find.byType(Scrollable),
      )
      .first;
  await tester.scrollUntilVisible(tile, 250, scrollable: scrollable);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
  final button = find.descendant(of: tile, matching: find.byType(FilledButton));
  await tester.tap(button);
  await tester.pump();
}

SegmentedButton<WidgetDisplayMode> _styleSelector(WidgetTester tester) =>
    tester.widget<SegmentedButton<WidgetDisplayMode>>(
      find.byWidgetPredicate(
        (widget) => widget is SegmentedButton<WidgetDisplayMode>,
      ),
    );

FilledButton _addButton(WidgetTester tester, DuoyiWidgetKind kind) =>
    tester.widget<FilledButton>(
      find
          .descendant(
            of: find.byKey(ValueKey(kind)),
            matching: find.byType(FilledButton),
          )
          .first,
    );

Future<void> _waitForStyleChange(
  WidgetTester tester,
  WidgetDisplayMode mode,
) async {
  for (var attempt = 0; attempt < 30; attempt++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
    final selector = _styleSelector(tester);
    if (selector.selected.single == mode &&
        selector.onSelectionChanged != null) {
      return;
    }
  }
  expect(_styleSelector(tester).selected, {mode});
  expect(_styleSelector(tester).onSelectionChanged, isNotNull);
}

Future<void> _selectCategory(
  WidgetTester tester,
  WidgetCategory category, {
  bool settle = true,
}) async {
  final segmented = find.byWidgetPredicate(
    (widget) => widget is SegmentedButton<WidgetCategory>,
  );
  final scrollable = find
      .descendant(
        of: find.byType(ListView).first,
        matching: find.byType(Scrollable),
      )
      .first;
  await tester.scrollUntilVisible(segmented, -250, scrollable: scrollable);
  final label = WidgetUiCopy.categoryLabel(category);
  await tester.tap(find.descendant(of: segmented, matching: find.text(label)));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> _waitFor(WidgetTester tester, Future<void> future) async {
  await tester.runAsync(() => future.timeout(const Duration(seconds: 3)));
  await tester.pump();
}

Future<void> _release(
  WidgetTester tester,
  Completer<Object?> gate,
  Object? value,
) async {
  await tester.runAsync(() async {
    if (!gate.isCompleted) gate.complete(value);
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });
  await tester.pumpAndSettle();
}

class _Fixture {
  _Fixture({this.styleStore, this.loadThemeFromStorage = true});
  final _WidgetStyleStore? styleStore;
  final bool loadThemeFromStorage;
  final theme = ThemeProvider();
  final lock = _MutableLock();
  final auth = _MutableAuthProvider();
  final updater = _MutableUpdateService();
  final channels = _WidgetChannels();
  final navigatorKey = GlobalKey<NavigatorState>();
  final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  final activityRevision = ValueNotifier(0);
  bool _installed = false;
  bool _disposed = false;

  Future<void> mount(
    WidgetTester tester, {
    WidgetHostPlatform hostPlatform = WidgetHostPlatform.android,
    bool isActive = true,
    bool settle = true,
    Size viewport = const Size(390, 844),
    bool pushAsSecondaryRoute = false,
  }) async {
    if (!_installed) {
      _installed = true;
      if (styleStore != null) {
        SharedPreferencesStorePlatform.instance = styleStore!;
      }
      tester.view.physicalSize = viewport;
      tester.view.devicePixelRatio = 1;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('duoyi/widgets'),
        channels.handleWidgets,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('duoyi/widget_pin_results'),
        channels.handlePinResults,
      );
      if (loadThemeFromStorage) await theme.loadFromStorage();
      addTearDown(() async {
        final release = styleStore?.release;
        if (release != null && !release.isCompleted) release.complete(false);
        final readRelease = styleStore?.getAllRelease;
        if (readRelease != null && !readRelease.isCompleted) {
          readRelease.complete(<String, Object>{});
        }
        await AccountPreferenceWrites.drain();
        channels.releasePendingGates();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        final defaultMessenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        defaultMessenger.setMockMethodCallHandler(
          const MethodChannel('duoyi/widgets'),
          null,
        );
        defaultMessenger.setMockMethodCallHandler(
          const MethodChannel('duoyi/widget_pin_results'),
          null,
        );
        AndroidWidgetManager.debugIsAndroidOverride = null;
        tester.view.reset();
        if (!_disposed) {
          _disposed = true;
          theme.dispose();
          lock.dispose();
          auth.dispose();
          updater.dispose();
          activityRevision.dispose();
        }
      });
    }

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>.value(value: theme),
          ChangeNotifierProvider<AppLockProvider>.value(value: lock),
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<AppUpdateService>.value(value: updater),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          scaffoldMessengerKey: scaffoldMessengerKey,
          debugShowCheckedModeBanner: false,
          theme: theme.brand.theme,
          home: pushAsSecondaryRoute
              ? const Scaffold(body: Text('More applications'))
              : IndexedStack(
                  index: isActive ? 0 : 1,
                  children: [
                    WidgetScreen(
                      key: const ValueKey('widget-screen'),
                      hostPlatform: hostPlatform,
                      isActive: isActive,
                      activityRevision: activityRevision,
                    ),
                    const Scaffold(body: Text('Other retained tab')),
                  ],
                ),
        ),
      ),
    );
    if (pushAsSecondaryRoute) {
      unawaited(
        navigatorKey.currentState!.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => BrandRouteSurface(
              child: WidgetScreen(
                key: const ValueKey('secondary-widget-screen'),
                hostPlatform: hostPlatform,
              ),
            ),
          ),
        ),
      );
    }
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> cover(
    WidgetTester tester, {
    required String label,
    bool settle = true,
  }) async {
    unawaited(
      navigatorKey.currentState!.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(body: Center(child: Text(label))),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }
  }
}

class _WidgetStyleStore extends InMemorySharedPreferencesStore {
  _WidgetStyleStore({Map<String, Object> initialValues = const {}})
    : super.withData(initialValues);
  int modeWrites = 0;
  int getAllCalls = 0;
  Completer<void>? started;
  Completer<bool>? release;
  Completer<void>? getAllStarted;
  Completer<Map<String, Object>>? getAllRelease;
  bool _holdGetAll = false;

  void holdNextGetAll() {
    getAllStarted = Completer<void>();
    getAllRelease = Completer<Map<String, Object>>();
    _holdGetAll = true;
  }

  void holdModeWrite() {
    started = Completer<void>();
    release = Completer<bool>();
  }

  @override
  Future<Map<String, Object>> getAll() async {
    getAllCalls++;
    if (_holdGetAll) {
      _holdGetAll = false;
      getAllStarted!.complete();
      return getAllRelease!.future;
    }
    return super.getAll();
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == 'flutter.duoyi_widget_display_mode') {
      modeWrites++;
      if (started != null && !started!.isCompleted) {
        started!.complete();
        if (!await release!.future) return false;
      }
    }
    return super.setValue(type, key, value);
  }
}

class _MutableLock extends AppLockProvider {
  bool _locked = false;

  @override
  bool get isLocked => _locked;

  void setLocked(bool value) {
    _locked = value;
    notifyListeners();
  }
}

class _MutableAuthProvider extends AuthProvider {
  int _generation = 0;

  @override
  int get sessionGeneration => _generation;

  void switchAccount() {
    _generation++;
    notifyListeners();
  }
}

class _MutableUpdateService extends AppUpdateService {
  _MutableUpdateService()
    : super(repo: 'dq52099/duoyi', currentVersion: '1.0.0');

  void setMustUpdate(bool value) {
    debugSetUpdatePolicyForTest(
      latestVersion: value ? '2.0.0' : null,
      minimumSupportedVersion: value ? '2.0.0' : null,
      forceUpdateRequired: value,
    );
    notifyListeners();
  }
}

class _WidgetChannels {
  final List<String> methodCalls = [];
  final List<String> pinWaitCalls = [];
  final List<Object?> supportReplies = [];
  int supportCalls = 0;
  int canOpenSettingsCalls = 0;
  int openSettingsCalls = 0;
  int pinRequestCalls = 0;
  final List<String?> pinRequestStyles = [];
  String nextPinRequestStatus = 'requested';
  String? pendingPinResultRequestId;
  Completer<Object?>? supportCheckGate;
  Completer<void>? supportCheckStarted;
  int _holdSupportAtCall = -1;
  Completer<Object?>? pinResultGate;
  Completer<void>? pinResultStarted;
  bool _hasHeldPinResult = false;

  void holdNextSupportCheck() {
    supportCheckGate = Completer<Object?>();
    supportCheckStarted = Completer<void>();
    _holdSupportAtCall = supportCalls + 1;
  }

  void holdNextPinResult() {
    pinResultGate = Completer<Object?>();
    pinResultStarted = Completer<void>();
    _hasHeldPinResult = false;
  }

  void releasePendingGates() {
    final supportGate = supportCheckGate;
    if (supportGate != null && !supportGate.isCompleted) {
      supportGate.complete(false);
    }
    final resultGate = pinResultGate;
    if (resultGate != null && !resultGate.isCompleted) {
      final requestId = pendingPinResultRequestId;
      resultGate.complete(
        requestId == null
            ? null
            : <String, Object>{
                'requestId': requestId,
                'status': 'confirmed',
                'kind': 'todo',
                'style': 'standard',
                'widgetId': 41,
              },
      );
    }
  }

  Future<Object?> handleWidgets(MethodCall call) async {
    methodCalls.add(call.method);
    switch (call.method) {
      case 'canRequestPinWidget':
        supportCalls++;
        if (supportCalls == _holdSupportAtCall) {
          _holdSupportAtCall = -1;
          supportCheckStarted!.complete();
          return supportCheckGate!.future;
        }
        if (supportReplies.isNotEmpty) return supportReplies.removeAt(0);
        return true;
      case 'canOpenWidgetSettings':
        canOpenSettingsCalls++;
        return true;
      case 'openWidgetSettings':
        openSettingsCalls++;
        return true;
      case 'requestPinWidget':
        pinRequestCalls++;
        final args = call.arguments as Map<Object?, Object?>?;
        pinRequestStyles.add(args?['style']?.toString());
        final status = nextPinRequestStatus;
        nextPinRequestStatus = 'requested';
        if (status == 'requested') {
          return 'requested:widget-pin-$pinRequestCalls';
        }
        return status;
      case 'lastPinResult':
        final args = call.arguments as Map<Object?, Object?>?;
        pendingPinResultRequestId = args?['requestId']?.toString();
        if (pinResultGate != null && !_hasHeldPinResult) {
          _hasHeldPinResult = true;
          pinResultStarted!.complete();
          return pinResultGate!.future;
        }
        return null;
      case 'applyWidgetDisplayMode':
      case 'refreshAllWidgets':
        return 0;
      case 'clearPinResult':
      case 'cancelPinRequest':
        return null;
      default:
        return null;
    }
  }

  Future<Object?> handlePinResults(MethodCall call) async {
    pinWaitCalls.add(call.method);
    return switch (call.method) {
      'beginWait' => 'widget-pin-receipt',
      _ => null,
    };
  }
}
