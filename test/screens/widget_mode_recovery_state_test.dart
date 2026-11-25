import 'dart:async';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/widget_ui_copy.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/widget_screen.dart';
import 'package:duoyi/services/home_widget_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'failed display mode sync survives remount and retries on ordinary refresh',
    (tester) async {
      final fixture = _WidgetModeRecoveryFixture(localMode: 'standard');
      await fixture.install(tester);
      addTearDown(() => fixture.dispose(tester));

      fixture.native.failNextDisplayModeSave = true;
      _styleSelector(tester).onSelectionChanged!({WidgetDisplayMode.detailed});
      await tester.pump();
      await tester.runAsync(
        () => fixture.native.firstDisplayModeSaveAttempted.future.timeout(
          const Duration(seconds: 3),
        ),
      );
      await _settleAsyncWork(tester);

      final prefs = await SharedPreferences.getInstance();
      final localModeAfterFailure = prefs.getString(
        'duoyi_widget_display_mode',
      );
      final nativeModeAfterFailure =
          fixture.native.values['widget_display_mode'];

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await fixture.mount(tester);

      // Capture both recovery affordances before refreshing. Keep going so the
      // final assertions also report the native writes and refresh result.
      final pendingVisibleAfterRemount = _hasKey(
        tester,
        'widget_style_sync_pending',
      );
      final retryVisibleAfterRemount = _hasKey(
        tester,
        'widget_style_sync_retry',
      );

      await tester.tap(find.byTooltip(WidgetUiCopy.refreshTooltip));
      await tester.runAsync(
        () => fixture.ordinaryRefreshCompleted.future.timeout(
          const Duration(seconds: 3),
        ),
      );
      await _settleAsyncWork(tester);

      final pendingVisibleAfterRefresh = _hasKey(
        tester,
        'widget_style_sync_pending',
      );
      final retryVisibleAfterRefresh = _hasKey(
        tester,
        'widget_style_sync_retry',
      );
      final nativeModeSaveValues = List<Object?>.of(
        fixture.native.displayModeSaveValues,
      );
      final nativeModeSaveCount = fixture.native.displayModeSaveValues.length;
      final successfulNativeModeSaveValues = List<Object?>.of(
        fixture.native.successfulDisplayModeSaveValues,
      );
      final nativeModeAfterRefresh =
          fixture.native.values['widget_display_mode'];
      final ordinaryRefreshCount = fixture.ordinaryRefreshCalls;

      expect(localModeAfterFailure, 'detailed');
      expect(nativeModeAfterFailure, 'standard');
      expect(
        {
          'pendingAfterRemount': pendingVisibleAfterRemount,
          'retryAfterRemount': retryVisibleAfterRemount,
          'nativeModeSaves': nativeModeSaveCount,
          'nativeModeAfterRefresh': nativeModeAfterRefresh,
          'ordinaryRefreshCalls': ordinaryRefreshCount,
        },
        {
          'pendingAfterRemount': true,
          'retryAfterRemount': true,
          'nativeModeSaves': 2,
          'nativeModeAfterRefresh': 'detailed',
          'ordinaryRefreshCalls': 1,
        },
      );
      expect(nativeModeSaveValues, ['detailed', 'detailed']);
      expect(successfulNativeModeSaveValues, ['detailed']);
      expect(nativeModeAfterRefresh, 'detailed');
      expect(ordinaryRefreshCount, 1);
      expect(pendingVisibleAfterRefresh, isFalse);
      expect(retryVisibleAfterRefresh, isFalse);
    },
  );

  testWidgets(
    'ordinary refresh does not publish a local mode without a pending sync',
    (tester) async {
      final fixture = _WidgetModeRecoveryFixture(localMode: 'detailed');
      await fixture.install(tester);
      addTearDown(() => fixture.dispose(tester));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await fixture.mount(tester);

      final detailedModeLoaded = _styleSelector(
        tester,
      ).selected.contains(WidgetDisplayMode.detailed);
      final pendingVisibleBeforeRefresh = _hasKey(
        tester,
        'widget_style_sync_pending',
      );
      final retryVisibleBeforeRefresh = _hasKey(
        tester,
        'widget_style_sync_retry',
      );

      await tester.tap(find.byTooltip(WidgetUiCopy.refreshTooltip));
      await tester.runAsync(
        () => fixture.ordinaryRefreshCompleted.future.timeout(
          const Duration(seconds: 3),
        ),
      );
      await _settleAsyncWork(tester);

      final nativeModeSaveCount = fixture.native.displayModeSaveValues.length;
      final nativeModeSaveValues = List<Object?>.of(
        fixture.native.displayModeSaveValues,
      );
      final nativeModeAfterRefresh =
          fixture.native.values['widget_display_mode'];
      final pendingVisibleAfterRefresh = _hasKey(
        tester,
        'widget_style_sync_pending',
      );
      final ordinaryRefreshCount = fixture.ordinaryRefreshCalls;

      expect(detailedModeLoaded, isTrue);
      expect(pendingVisibleBeforeRefresh, isFalse);
      expect(retryVisibleBeforeRefresh, isFalse);
      expect(nativeModeSaveCount, 0);
      expect(nativeModeSaveValues, isEmpty);
      expect(nativeModeAfterRefresh, 'standard');
      expect(pendingVisibleAfterRefresh, isFalse);
      expect(ordinaryRefreshCount, 1);
    },
  );
}

SegmentedButton<WidgetDisplayMode> _styleSelector(WidgetTester tester) =>
    tester.widget<SegmentedButton<WidgetDisplayMode>>(
      find.byWidgetPredicate(
        (widget) => widget is SegmentedButton<WidgetDisplayMode>,
      ),
    );

bool _hasKey(WidgetTester tester, String key) =>
    find.byKey(ValueKey(key)).evaluate().isNotEmpty;

Future<void> _settleAsyncWork(WidgetTester tester) async {
  for (var attempt = 0; attempt < 4; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

class _WidgetModeRecoveryFixture {
  _WidgetModeRecoveryFixture({required String localMode})
    : settings = _LocalWidgetSettingsStore(
        initialValues: <String, Object>{
          'flutter.duoyi_widget_display_mode': localMode,
        },
      );

  static const _channel = MethodChannel('home_widget');

  final _LocalWidgetSettingsStore settings;
  final _NativeWidgetStore native = _NativeWidgetStore();
  final ThemeProvider theme = ThemeProvider();
  final Completer<void> ordinaryRefreshCompleted = Completer<void>();
  late final SharedPreferencesStorePlatform _previousSettingsStore;
  late final Future<bool> Function()? _previousDashboardRefresher;
  late final bool? _previousSupportedForTesting;
  int ordinaryRefreshCalls = 0;

  Future<void> install(WidgetTester tester) async {
    _previousSettingsStore = SharedPreferencesStorePlatform.instance;
    _previousDashboardRefresher = HomeWidgetService.dashboardDataRefresher;
    _previousSupportedForTesting = HomeWidgetService.supportedForTesting;
    I18n.setLocale(AppLocale.zh);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SharedPreferencesStorePlatform.instance = settings;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, native.handle);
    HomeWidgetService.supportedForTesting = true;
    native.values['widget_display_mode'] = 'standard';
    native.displayModeSaveValues.clear();
    native.successfulDisplayModeSaveValues.clear();

    HomeWidgetService.dashboardDataRefresher = () async {
      ordinaryRefreshCalls++;
      final result = await HomeWidgetService.refreshPublishedWidgets();
      if (!ordinaryRefreshCompleted.isCompleted) {
        ordinaryRefreshCompleted.complete();
      }
      return result;
    };

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    await mount(tester);
  }

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: theme,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: const WidgetScreen(hostPlatform: WidgetHostPlatform.android),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> dispose(WidgetTester tester) async {
    await AccountPreferenceWrites.drain();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    HomeWidgetService.dashboardDataRefresher = _previousDashboardRefresher;
    HomeWidgetService.supportedForTesting = _previousSupportedForTesting;
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = _previousSettingsStore;
    tester.view.reset();
    I18n.setLocale(AppLocale.zh);
    theme.dispose();
  }
}

class _LocalWidgetSettingsStore extends InMemorySharedPreferencesStore {
  _LocalWidgetSettingsStore({required Map<String, Object> initialValues})
    : super.withData(initialValues);
}

class _NativeWidgetStore {
  final Map<String, Object?> values = <String, Object?>{};
  final List<Object?> displayModeSaveValues = <Object?>[];
  final List<Object?> successfulDisplayModeSaveValues = <Object?>[];
  final Completer<void> firstDisplayModeSaveAttempted = Completer<void>();
  bool failNextDisplayModeSave = false;

  Future<Object?> handle(MethodCall call) async {
    final args = call.arguments as Map?;
    switch (call.method) {
      case 'setAppGroupId':
        return true;
      case 'getWidgetData':
        return values[args!['id']];
      case 'saveWidgetData':
        final key = args!['id'] as String;
        final value = args['data'];
        if (key == 'widget_display_mode') {
          displayModeSaveValues.add(value);
          if (!firstDisplayModeSaveAttempted.isCompleted) {
            firstDisplayModeSaveAttempted.complete();
          }
          if (failNextDisplayModeSave) {
            failNextDisplayModeSave = false;
            return false;
          }
          successfulDisplayModeSaveValues.add(value);
        }
        values[key] = value;
        return true;
      case 'updateWidget':
        return true;
      default:
        return null;
    }
  }
}
