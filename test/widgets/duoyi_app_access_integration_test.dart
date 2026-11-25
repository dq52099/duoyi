import 'dart:async';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/app_update_ui_copy.dart';
import 'package:duoyi/main.dart';
import 'package:duoyi/providers/achievement_provider.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/focus_room_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/lock_screen.dart';
import 'package:duoyi/screens/login_screen.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:duoyi/widgets/force_update_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.en);
  });
  tearDown(() => I18n.setLocale(AppLocale.zh));

  for (final kind in ['page', 'dialog', 'sheet']) {
    testWidgets('production root locks and retains a $kind draft', (
      tester,
    ) async {
      final f = await _mount(tester);
      final controller = TextEditingController(text: 'original draft');
      addTearDown(controller.dispose);
      final editor = TextField(
        key: const ValueKey('editor'),
        controller: controller,
      );
      final context = tester.element(find.byType(Navigator));
      final navigator = Navigator.of(context);
      switch (kind) {
        case 'page':
          unawaited(
            navigator.push(
              MaterialPageRoute<void>(builder: (_) => Scaffold(body: editor)),
            ),
          );
        case 'dialog':
          unawaited(
            showDialog<void>(
              context: context,
              builder: (_) => AlertDialog(content: editor),
            ),
          );
        case 'sheet':
          unawaited(
            showModalBottomSheet<void>(
              context: context,
              builder: (_) =>
                  Padding(padding: const EdgeInsets.all(24), child: editor),
            ),
          );
      }
      await tester.pumpAndSettle();
      final route = ModalRoute.of(
        tester.element(find.byKey(const ValueKey('editor'))),
      )!;
      await tester.tap(find.byKey(const ValueKey('editor')));
      await tester.enterText(
        find.byKey(const ValueKey('editor')),
        'retained draft',
      );
      controller.selection = const TextSelection(
        baseOffset: 1,
        extentOffset: 5,
      );
      final focus = FocusManager.instance.primaryFocus!;
      f.lock.lock();
      expect(
        route.popDisposition,
        RoutePopDisposition.doNotPop,
        reason: 'root listener must block the actual route synchronously',
      );
      await tester.pumpAndSettle();
      expect(find.byType(LockScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('editor')).hitTestable(), findsNothing);
      expect(focus.hasFocus, isFalse);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(route.isCurrent, isTrue);
      await f.lock.unlockWith('2468');
      await tester.pumpAndSettle();
      expect(find.byType(LockScreen), findsNothing);
      expect(route.isCurrent, isTrue);
      expect(controller.text, 'retained draft');
      expect(
        controller.selection,
        const TextSelection(baseOffset: 1, extentOffset: 5),
      );
      expect(focus.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('cold forced update defers home until policy clears', (
    tester,
  ) async {
    final f = await _mount(tester, initialUpdate: true);
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byType(MainShell), findsNothing);
    expect(find.text(AppUpdateUiCopy.requiredTitle()), findsOneWidget);
    f.updater.setRequired(false);
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    f.updater.setRequired(true);
    await tester.pumpAndSettle();
    expect(
      find.byType(LoginScreen),
      findsOneWidget,
      reason: 'the home stays mounted when a later policy arrives',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'production update removes a busy lock and rejects its late verification',
    (tester) async {
      final f = await _mount(tester);
      f.lock.lock();
      await tester.pumpAndSettle();
      for (final digit in '2468'.split('')) {
        await tester.tap(find.text(digit));
        await tester.pump();
      }
      final held = Completer<bool>();
      f.lock.verification = held;
      await tester.tap(find.byKey(const ValueKey('lock_screen_submit')));
      await tester.pump();
      f.updater.setRequired(true);
      await tester.pumpAndSettle();
      expect(find.byType(LockScreen), findsNothing);
      expect(find.byType(ForceUpdateGate), findsOneWidget);
      expect(find.text(AppUpdateUiCopy.requiredTitle()), findsOneWidget);
      held.complete(true);
      await tester.pumpAndSettle();
      expect(f.lock.isLocked, isTrue);
      f.updater.setRequired(false);
      await tester.pumpAndSettle();
      expect(find.byType(LockScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );
}

Future<({_HeldLock lock, _Updater updater})> _mount(
  WidgetTester tester, {
  bool initialUpdate = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final lock = _HeldLock();
  await lock.setPin('2468');
  final updater = _Updater()..required = initialUpdate;
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ChangeNotifierProvider<AuthProvider>(create: (_) => _BlockedAuth()),
        ChangeNotifierProvider<AppLockProvider>.value(value: lock),
        ChangeNotifierProvider<AppUpdateService>.value(value: updater),
        ChangeNotifierProvider(create: (_) => AchievementProvider()),
        ChangeNotifierProvider(create: (_) => FocusRoomProvider()),
        ChangeNotifierProvider(create: (_) => PomodoroProvider()),
        ChangeNotifierProvider(create: (_) => TodoProvider()),
        ChangeNotifierProvider(create: (_) => PreferencesProvider()),
        ChangeNotifierProvider(create: (_) => GoalProvider()),
      ],
      child: const DuoyiApp(),
    ),
  );
  addTearDown(lock.dispose);
  addTearDown(updater.dispose);
  await tester.pumpAndSettle();
  return (lock: lock, updater: updater);
}

// Use the real root and real secondary routes with a local login home. Network,
// startup hydration and native launcher delivery are outside this fixture.
class _BlockedAuth extends AuthProvider {
  @override
  bool get isLocalAccountDataBlocked => true;
}

class _HeldLock extends AppLockProvider {
  Completer<bool>? verification;
  @override
  Future<bool> verify(String pin) => verification?.future ?? super.verify(pin);
}

class _Updater extends AppUpdateService {
  _Updater() : super(repo: 'fixture/duoyi', currentVersion: '1.0.0');
  bool required = false;
  @override
  bool get mustUpdate => required;
  void setRequired(bool value) {
    required = value;
    notifyListeners();
  }

  @override
  Future<void> checkServerPolicyNow() async {}
}
