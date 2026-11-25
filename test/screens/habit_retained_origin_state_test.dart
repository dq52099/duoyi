import 'dart:async';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/habit.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/habit_detail_screen.dart';
import 'package:duoyi/screens/habit_screen.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/reminder_scheduler.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../test_support/recording_reminder_scheduler.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.zh);
  });
  tearDown(() => I18n.setLocale(AppLocale.zh));

  testWidgets('Retained Habit detail Edit rejects an account reset', (
    tester,
  ) async {
    final f = _Fixture();
    await f.pump(tester, detail: true);
    final oldEdit = tester
        .widget<IconButton>(
          find.ancestor(
            of: find.byIcon(Icons.edit_outlined),
            matching: find.byType(IconButton),
          ),
        )
        .onPressed!;
    AccountLocalDataCleaner.invalidateInFlightAccountWrites();
    f.habits.resetLocalState();
    await tester.runAsync(AccountLocalDataCleaner.clearSharedPreferences);
    await tester.runAsync(
      () => f.habits.addHabit(
        Habit(id: 'synthetic', name: 'Current account habit'),
      ),
    );
    await tester.pumpAndSettle();
    oldEdit();
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(f.habits.habits.single.name, 'Current account habit');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Covered retained Habit detail Edit cannot open an editor', (
    tester,
  ) async {
    final f = _Fixture();
    await f.pump(tester, detail: true);
    final oldEdit = tester
        .widget<IconButton>(
          find.ancestor(
            of: find.byIcon(Icons.edit_outlined),
            matching: find.byType(IconButton),
          ),
        )
        .onPressed!;
    await f.cover(tester);
    oldEdit();
    await tester.pumpAndSettle();
    expect(find.text('Covering Habit route'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Acknowledged Habit add under lock cannot submit twice', (
    tester,
  ) async {
    final f = _Fixture();
    await f.pump(tester);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, '习惯名称'),
      'Acknowledged synthetic habit',
    );
    final save = find.widgetWithText(ElevatedButton, '开启新习惯');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    final retainedSave = tester.widget<ElevatedButton>(save).onPressed!;
    await tester.runAsync(() async {
      f.scheduler.armHold();
      retainedSave();
      await f.scheduler.started.future.timeout(const Duration(seconds: 3));
    });
    f.lock.setLocked(true);
    await tester.pump();
    await f.releaseAndDrain(tester);
    expect(f.habits.habits, hasLength(2));
    expect(find.byType(BottomSheet), findsOneWidget);
    final writes = f.store.habitWrites;
    f.lock.setLocked(false);
    await tester.pump();
    await tester.runAsync(() async {
      retainedSave();
      await AccountPreferenceWrites.drain();
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    expect(f.habits.habits, hasLength(2));
    expect(f.store.habitWrites, writes);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Retained Habit editor Cancel is ignored under lock', (
    tester,
  ) async {
    final f = _Fixture();
    await f.pump(tester, detail: true);
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    final cancel = find.widgetWithText(TextButton, I18n.tr('action.cancel'));
    await tester.ensureVisible(cancel);
    final callback = tester.widget<TextButton>(cancel).onPressed!;
    f.lock.setLocked(true);
    await tester.pump();
    callback();
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    f.lock.setLocked(false);
    await tester.pump();
    callback();
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _Fixture {
  final store = _HabitStore();
  final habits = HabitProvider();
  final theme = ThemeProvider();
  final lock = _MutableLock();
  final scheduler = _HoldingScheduler();
  final navigator = GlobalKey<NavigatorState>();

  Future<void> pump(WidgetTester tester, {bool detail = false}) async {
    SharedPreferencesStorePlatform.instance = store;
    habits.scheduler = scheduler;
    await tester.runAsync(
      () => habits.addHabit(Habit(id: 'synthetic', name: 'Synthetic habit')),
    );
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() async {
      await releaseAndDrain(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      habits.dispose();
      theme.dispose();
      lock.dispose();
      tester.view.reset();
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<HabitProvider>.value(value: habits),
          ChangeNotifierProvider<ThemeProvider>.value(value: theme),
          ChangeNotifierProvider<AppLockProvider>.value(value: lock),
        ],
        child: MaterialApp(
          navigatorKey: navigator,
          theme: theme.brand.theme,
          home: detail
              ? const HabitDetailScreen(habitId: 'synthetic')
              : const HabitScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> cover(WidgetTester tester) async {
    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Covering Habit route')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> releaseAndDrain(WidgetTester tester) async {
    await tester.runAsync(() async {
      if (!scheduler.release.isCompleted) scheduler.release.complete();
      await AccountPreferenceWrites.drain();
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
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

class _HoldingScheduler extends RecordingReminderScheduler {
  bool hold = false;
  Completer<void> started = Completer<void>();
  Completer<void> release = Completer<void>();

  void armHold() {
    hold = true;
    started = Completer<void>();
    release = Completer<void>();
  }

  @override
  Future<void> syncHabits(
    Iterable<Habit> habits, {
    ReminderReconciliationBatch? batch,
  }) async {
    await super.syncHabits(habits, batch: batch);
    if (hold && !started.isCompleted) {
      started.complete();
      await release.future;
    }
  }
}

class _HabitStore extends InMemorySharedPreferencesStore {
  _HabitStore() : super.withData({});
  int habitWrites = 0;

  @override
  Future<bool> setValue(String type, String key, Object value) {
    if (key == 'flutter.habits') habitWrites++;
    return super.setValue(type, key, value);
  }
}
