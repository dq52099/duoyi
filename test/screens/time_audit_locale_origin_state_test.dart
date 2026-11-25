// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/time_entry.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/time_audit_provider.dart';
import 'package:duoyi/screens/time_audit_screen.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  setUp(() {
    I18n.setLocale(AppLocale.zh);
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => I18n.setLocale(AppLocale.zh));

  for (final branded in [false, true]) {
    testWidgets(
      'locale preserves page selection and open draft (brand=$branded)',
      (tester) async {
        await _pump(tester, branded: branded);
        await tester.tap(find.text(I18n.tr('time_audit.range.all')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(I18n.tr('time_audit.view.trend')));
        await tester.pumpAndSettle();
        final pageState = tester.state(find.byType(TimeAuditScreen));
        final selections = tester
            .widgetList<SegmentedButton>(
              find.byWidgetPredicate((w) => w is SegmentedButton),
            )
            .map((w) => Set<Object?>.of(w.selected))
            .toList();
        await _openDraft(tester);
        await tester.enterText(find.byType(TextField).first, 'Literal 草稿');
        final controller = tester
            .widget<TextField>(find.byType(TextField).first)
            .controller!;
        controller.selection = const TextSelection(
          baseOffset: 1,
          extentOffset: 4,
        );
        final sheetState = tester.state(
          find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_TimeEntrySheet',
          ),
        );
        for (final locale in [AppLocale.en, AppLocale.zh]) {
          I18n.setLocale(locale);
          await tester.pumpAndSettle();
          expect(tester.state(find.byType(TimeAuditScreen)), same(pageState));
          expect(
            tester.state(
              find.byWidgetPredicate(
                (w) => w.runtimeType.toString() == '_TimeEntrySheet',
              ),
            ),
            same(sheetState),
          );
          expect(
            tester.widget<TextField>(find.byType(TextField).first).controller,
            same(controller),
          );
          expect(controller.text, 'Literal 草稿');
          expect(
            controller.selection,
            const TextSelection(baseOffset: 1, extentOffset: 4),
          );
          expect(
            find.text(I18n.tr('time_audit.sheet.add_title')),
            findsOneWidget,
          );
          expect(find.text(I18n.tr('time_audit.title')), findsOneWidget);
        }
        await tester.tap(find.text(I18n.tr('action.cancel')));
        await tester.pumpAndSettle();
        final retained = tester
            .widgetList<SegmentedButton>(
              find.byWidgetPredicate((w) => w is SegmentedButton),
            )
            .map((w) => Set<Object?>.of(w.selected))
            .toList();
        expect(retained, selections);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final invalidation in ['reset', 'replacement', 'account']) {
    testWidgets('retained draft save rejects $invalidation', (tester) async {
      final f = await _pump(tester);
      await _openDraft(tester);
      await tester.enterText(find.byType(TextField).first, 'Old account draft');
      final save = _save(tester);
      if (invalidation == 'reset') {
        f.provider.resetLocalState();
      } else if (invalidation == 'replacement') {
        f.current.value = TimeAuditProvider();
      } else {
        AccountLocalDataCleaner.invalidateInFlightAccountWrites();
      }
      await tester.pump();
      save();
      await tester.pumpAndSettle();
      expect(f.provider.entries, isEmpty);
      expect(f.current.value.entries, isEmpty);
      expect(find.byType(TextField), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }

  for (final invalidation in ['reset', 'replacement', 'account']) {
    testWidgets('retained page actions reject $invalidation before acting', (
      tester,
    ) async {
      final provider = TimeAuditProvider();
      final now = DateTime.now();
      final entry = TimeEntry(
        id: 'shared-id',
        title: 'Old entry',
        startAt: now,
        endAt: now.add(const Duration(minutes: 25)),
      );
      await provider.add(entry);
      final f = await _pump(tester, provider: provider);
      final add = tester
          .widget<FloatingActionButton>(find.byType(FloatingActionButton))
          .onPressed!;
      final copy = tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is IconButton &&
                  widget.tooltip == I18n.tr('time_audit.copy_report'),
            ),
          )
          .onPressed!;
      final delete = tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is IconButton &&
                  widget.tooltip == I18n.tr('action.delete'),
            ),
          )
          .onPressed!;
      final open = tester
          .widget<AppSurfaceCard>(
            find
                .ancestor(
                  of: find.text('Old entry'),
                  matching: find.byType(AppSurfaceCard),
                )
                .first,
          )
          .onTap!;
      var clipboardWrites = 0;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') clipboardWrites++;
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      if (invalidation == 'reset') {
        provider.resetLocalState();
        await provider.add(entry.copyWith(title: 'New entry'));
      } else if (invalidation == 'replacement') {
        final replacement = TimeAuditProvider();
        await replacement.add(entry.copyWith(title: 'New entry'));
        f.current.value = replacement;
      } else {
        AccountLocalDataCleaner.invalidateInFlightAccountWrites();
        await provider.update(entry.copyWith(title: 'New entry'));
      }
      await tester.pumpAndSettle();
      copy();
      delete();
      open();
      add();
      await tester.pumpAndSettle();
      expect(f.current.value.entries.single.title, 'New entry');
      expect(clipboardWrites, 0);
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'sheet cannot acquire owner changed between push and first mount',
    (tester) async {
      final f = await _pump(tester);
      tester
          .widget<FloatingActionButton>(find.byType(FloatingActionButton))
          .onPressed!();
      // The modal route is pushed, but its builder has not mounted yet.
      f.provider.resetLocalState();
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Old launch draft');
      _save(tester)();
      await tester.pumpAndSettle();
      expect(f.provider.entries, isEmpty);
      expect(find.byType(TextField), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('rejected draft save retries one stable identity', (
    tester,
  ) async {
    final store = _Store();
    SharedPreferencesStorePlatform.instance = store;
    final f = await _pump(tester);
    await _openDraft(tester);
    await tester.enterText(find.byType(TextField).first, 'Retry draft');
    store.rejectNext = true;
    _save(tester)();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(TextField), findsWidgets);
    expect(f.provider.entries, isEmpty);
    final rejected = store.attemptedEntries.single;
    final feedback = find.descendant(
      of: find.byType(SnackBar),
      matching: find.byType(Text),
    );
    final originalFeedback = tester
        .widgetList<Text>(feedback)
        .map((text) => text.data ?? '')
        .join(' ');
    expect(originalFeedback, isNotEmpty);
    I18n.setLocale(AppLocale.en);
    await tester.pump();
    final translatedFeedback = tester
        .widgetList<Text>(feedback)
        .map((text) => text.data ?? '')
        .join(' ');
    expect(translatedFeedback, isNot(originalFeedback));
    expect(translatedFeedback, isNot(contains('StateError')));
    expect(translatedFeedback, isNot(matches(RegExp(r'[\u3400-\u9fff]'))));
    await tester.enterText(find.byType(TextField).first, 'Retried title');
    _save(tester)();
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(store.attempts, 2);
    expect(f.provider.entries, hasLength(1));
    expect(f.provider.entries.single.id, rejected.id);
    expect(f.provider.entries.single.createdAt, rejected.createdAt);
    expect(f.provider.entries.single.title, 'Retried title');
  });

  testWidgets('failed new draft keeps its identity through a storage reload', (
    tester,
  ) async {
    final store = _Store();
    SharedPreferencesStorePlatform.instance = store;
    final f = await _pump(tester);
    await _openDraft(tester);
    store.rejectNext = true;
    _save(tester)();
    await tester.pumpAndSettle();
    expect(f.provider.entries, isEmpty);
    final identity = store.attemptedEntries.single.id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    await f.provider.loadFromStorage();
    await tester.pumpAndSettle();
    expect(f.provider.entries, isEmpty);
    _save(tester)();
    await tester.pumpAndSettle();
    expect(store.attempts, 2);
    expect(f.provider.entries.single.id, identity);
    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending rejected save cannot show feedback after source reset', (
    tester,
  ) async {
    final store = _Store();
    SharedPreferencesStorePlatform.instance = store;
    final f = await _pump(tester);
    await _openDraft(tester);
    store.gate = Completer<void>();
    store.rejectNext = true;
    _save(tester)();
    await tester.pump();
    expect(store.attempts, 1);
    f.provider.resetLocalState();
    store.gate!.complete();
    await tester.pumpAndSettle();
    expect(f.provider.entries, isEmpty);
    expect(find.byType(TextField), findsWidgets);
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final rejected in [false, true]) {
    testWidgets('pending save preserves covering route (rejected=$rejected)', (
      tester,
    ) async {
      final store = _Store();
      SharedPreferencesStorePlatform.instance = store;
      final f = await _pump(tester);
      await _openDraft(tester);
      final save = _save(tester);
      store.gate = Completer<void>();
      store.rejectNext = rejected;
      save();
      save();
      await tester.pump();
      expect(store.attempts, 1);
      f.navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Covering route')),
        ),
      );
      await tester.pumpAndSettle();
      store.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Covering route'), findsOneWidget);
      expect(f.provider.entries, hasLength(rejected ? 0 : 1));
      expect(store.attempts, 1);
      expect(find.byType(SnackBar), findsNothing);
      f.navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.byType(TextField), rejected ? findsWidgets : findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('deleted existing entry cannot be recreated by retained save', (
    tester,
  ) async {
    final provider = TimeAuditProvider();
    final now = DateTime.now();
    await provider.add(
      TimeEntry(
        id: 'existing',
        title: 'Existing entry',
        startAt: now,
        endAt: now.add(const Duration(minutes: 25)),
      ),
    );
    await _pump(tester, provider: provider);
    await tester.tap(find.text('Existing entry'));
    await tester.pumpAndSettle();
    final save = _save(tester);
    await provider.delete('existing');
    await tester.pump();
    save();
    await tester.pumpAndSettle();
    expect(provider.entries, isEmpty);
    expect(find.byType(TextField), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('initial entry opens once across repeated locale changes', (
    tester,
  ) async {
    final provider = TimeAuditProvider();
    final now = DateTime.now();
    await provider.add(
      TimeEntry(
        id: 'initial',
        title: 'Initial entry',
        startAt: now,
        endAt: now.add(const Duration(minutes: 25)),
      ),
    );
    await _pump(
      tester,
      provider: provider,
      branded: true,
      initialId: 'initial',
    );
    expect(find.byType(TextField), findsWidgets);
    for (final locale in [AppLocale.en, AppLocale.zh, AppLocale.en]) {
      I18n.setLocale(locale);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text(I18n.tr('action.cancel')));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    I18n.setLocale(AppLocale.zh);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);
  });
  for (final change in ['delete', 'reorder']) {
    testWidgets(
      'initial entry resolves identity after committed $change before mount',
      (tester) async {
        final provider = TimeAuditProvider();
        final now = DateTime.now();
        await provider.add(
          TimeEntry(
            id: 'target',
            title: 'Target entry',
            startAt: now,
            endAt: now.add(const Duration(minutes: 25)),
          ),
        );
        // Only acknowledged mutations change the provider's visible snapshot.
        // Complete the concurrent change before the route's first frame.
        if (change == 'delete') {
          await provider.delete('target');
        } else {
          await provider.add(
            TimeEntry(
              id: 'newer',
              title: 'Different entry',
              startAt: now.add(const Duration(hours: 1)),
              endAt: now.add(const Duration(hours: 2)),
            ),
          );
        }
        await _pump(tester, provider: provider, initialId: 'target');
        if (change == 'delete') {
          expect(find.byType(TextField), findsNothing);
        } else {
          expect(
            tester
                .widget<TextField>(find.byType(TextField).first)
                .controller!
                .text,
            'Target entry',
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('pending initial ID cannot bind to a later account generation', (
    tester,
  ) async {
    final f = await _pump(tester, initialId: 'late-entry');
    expect(find.byType(TextField), findsNothing);
    f.provider.resetLocalState();
    final now = DateTime.now();
    await f.provider.add(
      TimeEntry(
        id: 'late-entry',
        title: 'New owner entry',
        startAt: now,
        endAt: now.add(const Duration(minutes: 25)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<_Fixture> _pump(
  WidgetTester tester, {
  TimeAuditProvider? provider,
  bool branded = false,
  String? initialId,
}) async {
  tester.view.resetPhysicalSize();
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final original = provider ?? TimeAuditProvider();
  final current = ValueNotifier(original);
  final navigator = GlobalKey<NavigatorState>();
  final screen = TimeAuditScreen(initialEntryId: initialId);
  await tester.pumpWidget(
    ValueListenableBuilder<TimeAuditProvider>(
      valueListenable: current,
      builder: (_, owner, _) => MultiProvider(
        providers: [
          ChangeNotifierProvider<TimeAuditProvider>.value(value: owner),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ],
        child: MaterialApp(
          navigatorKey: navigator,
          home: branded ? BrandRouteSurface(child: screen) : screen,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Fixture(original, current, navigator);
}

Future<void> _openDraft(WidgetTester tester) async {
  await tester.tap(find.text(I18n.tr('time_audit.add_manual')));
  await tester.pumpAndSettle();
}

VoidCallback _save(WidgetTester tester) => tester
    .widget<FilledButton>(
      find.widgetWithText(FilledButton, I18n.tr('action.save')),
    )
    .onPressed!;

class _Fixture {
  final TimeAuditProvider provider;
  final ValueNotifier<TimeAuditProvider> current;
  final GlobalKey<NavigatorState> navigator;
  _Fixture(this.provider, this.current, this.navigator);
}

class _Store extends InMemorySharedPreferencesStore {
  _Store() : super.withData({});
  bool rejectNext = false;
  int attempts = 0;
  final attemptedEntries = <TimeEntry>[];
  Completer<void>? gate;

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == 'flutter.${TimeAuditProvider.storageKey}') {
      attempts++;
      attemptedEntries.addAll(
        (value as List).cast<String>().map(
          (raw) => TimeEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>),
        ),
      );
      if (gate != null) await gate!.future;
      if (rejectNext) {
        rejectNext = false;
        return false;
      }
    }
    return super.setValue(type, key, value);
  }
}
