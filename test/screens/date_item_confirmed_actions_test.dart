// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/date_item_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/anniversary.dart';
import 'package:duoyi/models/countdown.dart';
import 'package:duoyi/providers/anniversary_provider.dart';
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:duoyi/screens/anniversary_screen.dart';
import 'package:duoyi/screens/countdown_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Store store;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = _Store();
    SharedPreferencesStorePlatform.instance = store;
    I18n.setLocale(AppLocale.zh);
  });

  tearDown(() async {
    store.releaseAll();
    await AccountPreferenceWrites.drain();
    I18n.setLocale(AppLocale.zh);
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  for (final dateCase in _dateCases) {
    testWidgets(
      '${dateCase.name} editor keeps rejected drafts, localizes feedback, and retries false/throw writes',
      (tester) async {
        final fixture = await dateCase.create(store);
        addTearDown(fixture.dispose);
        await tester.pumpWidget(fixture.tree(fixture.editorLauncher));

        for (final throws in [false, true]) {
          await tester.tap(find.byKey(const ValueKey('open_date_editor')));
          await tester.pumpAndSettle();
          final titleField = find.byType(TextField).first;
          final draft = throws ? 'Throw retry title' : 'False retry title';
          final confirmedBefore = fixture.title();
          await tester.enterText(titleField, draft);
          store.rejectNext(fixture.platformListKey, throws: throws);

          final save = find.byKey(fixture.saveButtonKey);
          await tester.ensureVisible(save);
          await tester.pumpAndSettle();
          expect(save.hitTestable(), findsOneWidget);
          await tester.tap(save);
          await tester.pumpAndSettle();

          expect(fixture.title(), confirmedBefore);
          expect(tester.widget<TextField>(titleField).controller!.text, draft);
          expect(find.text(DateItemUiCopy.saveFailed), findsOneWidget);
          expect(find.text(I18n.tr('action.retry')), findsOneWidget);
          expect(
            _storedTitle(fixture.preferences, fixture.storageKey),
            confirmedBefore,
          );

          if (!throws) {
            I18n.setLocale(AppLocale.en);
            await tester.pump();
            expect(find.text(DateItemUiCopy.saveFailed), findsOneWidget);
            expect(
              find.text(
                'Could not save. Your changes are still here. Please retry.',
              ),
              findsOneWidget,
            );
            I18n.setLocale(AppLocale.zh);
            await tester.pump();
            expect(find.text('未能保存，更改已保留，请重试。'), findsOneWidget);
          }

          final retry = find.text(I18n.tr('action.retry'));
          await tester.ensureVisible(retry);
          await tester.tap(retry);
          await tester.pumpAndSettle();

          expect(fixture.title(), draft);
          expect(_storedTitle(fixture.preferences, fixture.storageKey), draft);
          expect(find.byKey(fixture.saveButtonKey), findsNothing);
        }
      },
    );

    testWidgets(
      '${dateCase.name} editor ignores a second submit and discards a held write after closing',
      (tester) async {
        final fixture = await dateCase.create(store);
        addTearDown(fixture.dispose);
        final confirmedBefore = fixture.title();
        await tester.pumpWidget(fixture.tree(fixture.editorLauncher));
        await tester.tap(find.byKey(const ValueKey('open_date_editor')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, 'Held draft');

        store.holdNext(fixture.platformListKey);
        final submit = tester
            .widget<FilledButton>(find.byKey(fixture.saveButtonKey))
            .onPressed!;
        submit();
        await store.heldWriteStarted.timeout(const Duration(seconds: 2));
        await tester.pump();

        expect(fixture.title(), confirmedBefore);
        expect(fixture.persistedMutationCount(), 0);
        expect(store.writeCount(fixture.platformListKey), 1);
        expect(
          tester
              .widget<FilledButton>(find.byKey(fixture.saveButtonKey))
              .onPressed,
          isNull,
        );
        // Retained callbacks also obey the busy entry guard.
        submit();
        await tester.pump();
        expect(store.writeCount(fixture.platformListKey), 1);

        final cancel = find.widgetWithText(
          TextButton,
          I18n.tr('action.cancel'),
        );
        await tester.ensureVisible(cancel);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(cancel);
        await tester.pumpAndSettle();
        store.releaseAll();
        await AccountPreferenceWrites.drain();
        await tester.pumpAndSettle();

        expect(fixture.title(), confirmedBefore);
        expect(
          _storedTitle(fixture.preferences, fixture.storageKey),
          confirmedBefore,
        );
        expect(fixture.persistedMutationCount(), 0);
        expect(
          store.writeCount(fixture.platformListKey),
          2,
        ); // Write plus rollback.
        expect(find.byKey(fixture.saveButtonKey), findsNothing);
        expect(find.text(DateItemUiCopy.saveFailed), findsNothing);
      },
    );

    testWidgets(
      '${dateCase.name} card keeps a failed pin and retries the original target',
      (tester) async {
        final fixture = await dateCase.create(store);
        addTearDown(fixture.dispose);
        await tester.pumpWidget(fixture.tree(fixture.listPage));
        await tester.pumpAndSettle();
        final card = find.byKey(fixture.cardKey);
        await tester.ensureVisible(card);
        store.rejectNext(fixture.platformListKey, throws: false);

        await tester.longPress(card);
        await tester.pumpAndSettle();

        expect(fixture.pinned(), isFalse);
        expect(find.byKey(fixture.cardKey), findsOneWidget);
        expect(find.text(DateItemUiCopy.pinFailed), findsOneWidget);
        expect(_storedPinned(fixture.preferences, fixture.storageKey), isFalse);

        I18n.setLocale(AppLocale.en);
        await tester.pump();
        expect(
          find.text('Could not update pinning. Please retry.'),
          findsOneWidget,
        );
        I18n.setLocale(AppLocale.zh);
        await tester.pump();

        // A different action can satisfy the original request before Retry.
        // Retry must keep the captured "pinned = true" target instead of
        // toggling whatever value is current when the button is tapped.
        await fixture.setPinned(true);
        await tester.pumpAndSettle();
        final writesBeforeRetry = store.writeCount(fixture.platformListKey);
        final retry = find.text(I18n.tr('action.retry'));
        await tester.ensureVisible(retry);
        await tester.tap(retry);
        await tester.pumpAndSettle();

        expect(fixture.pinned(), isTrue);
        expect(_storedPinned(fixture.preferences, fixture.storageKey), isTrue);
        expect(store.writeCount(fixture.platformListKey), writesBeforeRetry);
        expect(find.byKey(fixture.cardKey), findsOneWidget);
        expect(find.text(DateItemUiCopy.pinFailed), findsNothing);
      },
    );
  }
}

class _Fixture {
  const _Fixture({
    required this.storageKey,
    required this.platformListKey,
    required this.saveButtonKey,
    required this.cardKey,
    required this.preferences,
    required this.tree,
    required this.editorLauncher,
    required this.listPage,
    required this.title,
    required this.pinned,
    required this.setPinned,
    required this.persistedMutationCount,
    required this.dispose,
  });

  final String storageKey;
  final String platformListKey;
  final ValueKey<String> saveButtonKey;
  final ValueKey<String> cardKey;
  final SharedPreferences preferences;
  final Widget Function(Widget home) tree;
  final Widget editorLauncher;
  final Widget listPage;
  final String Function() title;
  final bool Function() pinned;
  final Future<void> Function(bool pinned) setPinned;
  final int Function() persistedMutationCount;
  final void Function() dispose;
}

class _DateCase {
  const _DateCase(this.name, this.create);

  final String name;
  final Future<_Fixture> Function(_Store store) create;
}

final _dateCases = <_DateCase>[
  _DateCase('CountdownProvider', _countdownFixture),
  _DateCase('AnniversaryProvider', _anniversaryFixture),
];

Future<_Fixture> _countdownFixture(_Store store) async {
  final preferences = await SharedPreferences.getInstance();
  const id = 'confirmed-countdown';
  final item = CountdownItem(
    id: id,
    title: 'Confirmed title',
    targetDate: DateTime.now().add(const Duration(days: 30)),
    category: 'Test',
  );
  const storageKey = 'duoyi_countdowns';
  const platformListKey = 'flutter.duoyi_countdowns';
  await preferences.setStringList(storageKey, [jsonEncode(item.toJson())]);
  final provider = CountdownProvider();
  await provider.loadFromStorage();
  var persisted = 0;
  provider.onLocalMutationPersisted = () => persisted++;
  store.resetWrites();
  return _Fixture(
    storageKey: storageKey,
    platformListKey: platformListKey,
    saveButtonKey: const ValueKey('countdown_editor_save_button'),
    cardKey: const ValueKey('countdown_card_confirmed-countdown'),
    preferences: preferences,
    tree: (home) => ChangeNotifierProvider<CountdownProvider>.value(
      value: provider,
      child: MaterialApp(home: home),
    ),
    editorLauncher: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            key: const ValueKey('open_date_editor'),
            onPressed: () => showCountdownEditor(
              context,
              item: provider.items.singleWhere((item) => item.id == id),
            ),
            child: const Text('Open editor'),
          ),
        ),
      ),
    ),
    listPage: const CountdownScreen(),
    title: () => provider.items.single.title,
    pinned: () => provider.items.single.isPinned,
    setPinned: (pinned) => provider.setPinned(id, pinned),
    persistedMutationCount: () => persisted,
    dispose: provider.dispose,
  );
}

Future<_Fixture> _anniversaryFixture(_Store store) async {
  final preferences = await SharedPreferences.getInstance();
  const id = 'confirmed-anniversary';
  final item = Anniversary(
    id: id,
    title: 'Confirmed title',
    originDate: DateTime.now().add(const Duration(days: 30)),
    type: AnniversaryType.memorial,
  );
  const storageKey = 'duoyi_anniversaries_v2';
  const platformListKey = 'flutter.duoyi_anniversaries_v2';
  await preferences.setStringList(storageKey, [jsonEncode(item.toJson())]);
  final provider = AnniversaryProvider();
  await provider.loadFromStorage();
  var persisted = 0;
  provider.onLocalMutationPersisted = () => persisted++;
  store.resetWrites();
  return _Fixture(
    storageKey: storageKey,
    platformListKey: platformListKey,
    saveButtonKey: const ValueKey('anniversary_editor_save_button'),
    cardKey: const ValueKey('anniversary_card_confirmed-anniversary'),
    preferences: preferences,
    tree: (home) => ChangeNotifierProvider<AnniversaryProvider>.value(
      value: provider,
      child: MaterialApp(home: home),
    ),
    editorLauncher: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            key: const ValueKey('open_date_editor'),
            onPressed: () => showAnniversaryEditor(
              context,
              item: provider.items.singleWhere((item) => item.id == id),
              fixedType: AnniversaryType.memorial,
            ),
            child: const Text('Open editor'),
          ),
        ),
      ),
    ),
    listPage: const MemorialAnniversaryScreen(),
    title: () => provider.items.single.title,
    pinned: () => provider.items.single.isPinned,
    setPinned: (pinned) => provider.setPinned(id, pinned),
    persistedMutationCount: () => persisted,
    dispose: provider.dispose,
  );
}

String _storedTitle(SharedPreferences preferences, String key) {
  final item =
      jsonDecode(preferences.getStringList(key)!.single)
          as Map<String, dynamic>;
  return item['title'] as String;
}

bool _storedPinned(SharedPreferences preferences, String key) {
  final item =
      jsonDecode(preferences.getStringList(key)!.single)
          as Map<String, dynamic>;
  return item['isPinned'] == true;
}

class _Store extends InMemorySharedPreferencesStore {
  _Store() : super.withData(<String, Object>{});

  final Map<String, int> _writes = <String, int>{};
  String? _rejectKey;
  bool _throwOnRejection = false;
  String? _heldKey;
  Completer<void>? _heldWriteStarted;
  Completer<void>? _heldWriteRelease;

  Future<void> get heldWriteStarted => _heldWriteStarted!.future;

  int writeCount(String key) => _writes[key] ?? 0;

  void resetWrites() => _writes.clear();

  void rejectNext(String key, {required bool throws}) {
    _rejectKey = key;
    _throwOnRejection = throws;
  }

  void holdNext(String key) {
    _heldKey = key;
    _heldWriteStarted = Completer<void>();
    _heldWriteRelease = Completer<void>();
  }

  void releaseAll() {
    final release = _heldWriteRelease;
    if (release != null && !release.isCompleted) release.complete();
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    _writes.update(key, (count) => count + 1, ifAbsent: () => 1);
    if (_heldKey == key) {
      _heldKey = null;
      _heldWriteStarted!.complete();
      await _heldWriteRelease!.future;
    }

    // Simulate a platform that applies the value before rejecting the result.
    final saved = await super.setValue(type, key, value);
    if (_rejectKey == key) {
      final shouldThrow = _throwOnRejection;
      _rejectKey = null;
      _throwOnRejection = false;
      if (shouldThrow) throw StateError('injected platform write failure');
      return false;
    }
    return saved;
  }
}
