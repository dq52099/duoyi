import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/services/app_haptics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> platformCalls;
  late bool rejectHaptics;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    platformCalls = <MethodCall>[];
    rejectHaptics = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            platformCalls.add(call);
            if (rejectHaptics) {
              throw PlatformException(code: 'haptic_unavailable');
            }
          }
          return null;
        });
  });

  tearDown(() async {
    await AccountPreferenceWrites.drain();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('enabled haptic kinds dispatch their Flutter platform types', (
    tester,
  ) async {
    final preferences = PreferencesProvider();
    addTearDown(preferences.dispose);
    final context = await _pumpHapticHost(tester, preferences: preferences);

    for (final (kind, _) in <(AppHaptic, String)>[
      (AppHaptic.lightImpact, 'lightImpact'),
      (AppHaptic.mediumImpact, 'mediumImpact'),
      (AppHaptic.heavyImpact, 'heavyImpact'),
      (AppHaptic.selectionClick, 'selectionClick'),
    ]) {
      await performAppHaptic(context, kind);
    }

    expect(
      platformCalls.map((call) => call.method),
      everyElement('HapticFeedback.vibrate'),
    );
    expect(platformCalls.map((call) => call.arguments), [
      'HapticFeedbackType.lightImpact',
      'HapticFeedbackType.mediumImpact',
      'HapticFeedbackType.heavyImpact',
      'HapticFeedbackType.selectionClick',
    ]);
  });

  testWidgets('disabled preference dispatches no platform haptic', (
    tester,
  ) async {
    final preferences = PreferencesProvider();
    addTearDown(preferences.dispose);
    await preferences.setHaptic(false);
    final context = await _pumpHapticHost(tester, preferences: preferences);

    await performAppHaptic(context, AppHaptic.lightImpact);

    expect(platformCalls, isEmpty);
  });

  testWidgets('missing preferences source defaults to enabled', (tester) async {
    final context = await _pumpHapticHost(tester);

    await performAppHaptic(context, AppHaptic.selectionClick);

    expect(platformCalls, hasLength(1));
    expect(platformCalls.single.arguments, 'HapticFeedbackType.selectionClick');
  });

  testWidgets('each invocation reads the current haptic preference', (
    tester,
  ) async {
    final preferences = PreferencesProvider();
    addTearDown(preferences.dispose);
    final context = await _pumpHapticHost(tester, preferences: preferences);

    await performAppHaptic(context, AppHaptic.lightImpact);
    await preferences.setHaptic(false);
    await performAppHaptic(context, AppHaptic.mediumImpact);
    await preferences.setHaptic(true);
    await performAppHaptic(context, AppHaptic.selectionClick);

    expect(platformCalls.map((call) => call.arguments), [
      'HapticFeedbackType.lightImpact',
      'HapticFeedbackType.selectionClick',
    ]);
  });

  testWidgets('expired owner and unmounted context dispatch no haptics', (
    tester,
  ) async {
    final preferences = PreferencesProvider();
    addTearDown(preferences.dispose);
    final context = await _pumpHapticHost(tester, preferences: preferences);
    var ownerChecks = 0;

    await performAppHaptic(
      context,
      AppHaptic.heavyImpact,
      isCurrent: () {
        ownerChecks++;
        return false;
      },
    );
    expect(ownerChecks, 1);
    expect(platformCalls, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    await performAppHaptic(context, AppHaptic.heavyImpact);

    expect(platformCalls, isEmpty);
  });

  testWidgets('platform haptic errors complete normally', (tester) async {
    final context = await _pumpHapticHost(tester);
    rejectHaptics = true;

    await expectLater(
      performAppHaptic(context, AppHaptic.mediumImpact),
      completes,
    );

    expect(platformCalls, hasLength(1));
  });
}

Future<BuildContext> _pumpHapticHost(
  WidgetTester tester, {
  PreferencesProvider? preferences,
}) async {
  final contextKey = GlobalKey();
  final app = MaterialApp(
    home: Builder(
      builder: (context) =>
          Scaffold(body: SizedBox(key: contextKey, width: 1, height: 1)),
    ),
  );
  await tester.pumpWidget(
    preferences == null
        ? app
        : ChangeNotifierProvider<PreferencesProvider>.value(
            value: preferences,
            child: app,
          ),
  );
  await tester.pump();
  return tester.element(find.byKey(contextKey));
}
