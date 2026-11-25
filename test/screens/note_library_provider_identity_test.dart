// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/note.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/providers/note_provider.dart';
import 'package:duoyi/screens/note_screen.dart';
import 'package:duoyi/services/app_access_route_gate.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/widget_polish_screenshot_font.dart';

const _notesKey = 'duoyi_notes';
const _platformNotesKey = 'flutter.duoyi_notes';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    I18n.setLocale(AppLocale.zh);
  });

  tearDown(() => I18n.setLocale(AppLocale.zh));

  testWidgets(
    'replaced provider hides old failure and rejects retained retry, menu and card callbacks',
    (tester) async {
      final fixture = await _mount(tester);
      final oldProvider = fixture.oldProvider;
      final replacement = fixture.replacementProvider;
      expect(oldProvider.storageGeneration, 0);
      expect(replacement.storageGeneration, 0);
      expect(oldProvider.notes.single.id, replacement.notes.single.id);
      expect(
        oldProvider.notes.single.content,
        isNot(replacement.notes.single.content),
      );

      final library = find.byType(NoteScreen);
      final libraryState = tester.state<State<NoteScreen>>(library);
      final card = find.byKey(const ValueKey<String>('active-shared-note'));
      final retainedOpen = tester
          .widget<AppSurfaceCard>(
            find.descendant(of: card, matching: find.byType(AppSurfaceCard)),
          )
          .onTap!;
      final retainedPin = _retainPin(tester, card);
      fixture.store.failNextNoteWrite = true;
      await _selectPin(tester);
      await _drainWrites(tester);

      expect(oldProvider.notes.single.pinned, isFalse);
      expect(find.text(I18n.tr('note.action.failed')), findsOneWidget);
      final retainedRetry = tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, I18n.tr('action.retry')),
          )
          .onPressed!;
      final writesBeforeRetainedRetry = fixture.store.noteWriteAttempts;
      final prefs = await SharedPreferences.getInstance();
      expect(
        _storedNote(prefs, 'shared-note')!.content,
        'Replacement provider note\nnew body',
      );
      expect(_storedNote(prefs, 'shared-note')!.pinned, isFalse);

      fixture.activeProvider.value = replacement;
      await _pumpFrames(tester);
      expect(tester.state<State<NoteScreen>>(library), same(libraryState));
      expect(find.text('Replacement provider note'), findsOneWidget);
      expect(find.text(I18n.tr('note.action.failed')), findsNothing);
      expect(find.text(I18n.tr('action.retry')), findsNothing);
      expect(replacement.notes.single.pinned, isFalse);
      expect(
        replacement.notes.single.content,
        'Replacement provider note\nnew body',
      );

      retainedOpen();
      retainedPin();
      retainedRetry();
      await _drainWrites(tester);
      await _pumpFrames(tester);
      expect(find.byType(NoteEditScreen), findsNothing);
      expect(oldProvider.notes.single.pinned, isFalse);

      expect(fixture.store.noteWriteAttempts, writesBeforeRetainedRetry);
      expect(replacement.notes.single.pinned, isFalse);
      expect(
        replacement.notes.single.content,
        'Replacement provider note\nnew body',
      );
      expect(
        _storedNote(prefs, 'shared-note')!.content,
        'Replacement provider note\nnew body',
      );
      expect(_storedNote(prefs, 'shared-note')!.pinned, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'held old-provider pin rolls back after replacement without touching the replacement',
    (tester) async {
      final fixture = await _mount(tester);
      final oldProvider = fixture.oldProvider;
      final replacement = fixture.replacementProvider;
      final originalOld = oldProvider.notes.single.toJson();
      final originalReplacement = replacement.notes.single.toJson();
      final writesBeforeAction = fixture.store.noteWriteAttempts;
      expect(oldProvider.storageGeneration, replacement.storageGeneration);

      fixture.store.holdNextNoteWrite();
      await _selectPin(tester);
      await _waitForHeldWrite(tester, fixture.store);
      expect(oldProvider.notes.single.toJson(), equals(originalOld));
      expect(replacement.notes.single.toJson(), equals(originalReplacement));

      final library = find.byType(NoteScreen);
      final libraryState = tester.state<State<NoteScreen>>(library);
      fixture.activeProvider.value = replacement;
      await _pumpFrames(tester);
      expect(tester.state<State<NoteScreen>>(library), same(libraryState));
      expect(find.text('Replacement provider note'), findsOneWidget);
      expect(find.text(I18n.tr('note.action.failed')), findsNothing);
      expect(replacement.notes.single.toJson(), equals(originalReplacement));

      fixture.store.releaseNoteWrite();
      await _drainWrites(tester);

      final prefs = await SharedPreferences.getInstance();
      final persisted = _storedNote(prefs, 'shared-note')!;
      expect(oldProvider.notes.single.toJson(), equals(originalOld));
      expect(replacement.notes.single.toJson(), equals(originalReplacement));
      expect(persisted.toJson(), equals(originalReplacement));
      expect(persisted.pinned, isFalse);
      expect(fixture.store.noteWriteAttempts, writesBeforeAction + 2);
      expect(find.text(I18n.tr('note.action.failed')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'confirmed pin stays successful when its post-commit callback locks and covers the route',
    (tester) async {
      final fixture = await _mount(tester, replacementHasDistinctNote: false);
      var callbackCount = 0;
      fixture.oldProvider.onLocalMutationPersisted = () {
        callbackCount++;
        fixture.lock.setLocked(true);
        fixture.lock.setLocked(false);
        final navigator = fixture.navigator.currentState!;
        unawaited(
          navigator.push<void>(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Temporary cover')),
            ),
          ),
        );
        navigator.pop();
      };

      await _selectPin(tester);
      await _drainWrites(tester);

      expect(fixture.oldProvider.notes.single.pinned, isTrue);
      expect(callbackCount, 1);
      expect(find.text(I18n.tr('note.action.failed')), findsNothing);
      expect(find.text(I18n.tr('action.retry')), findsNothing);
      expect(fixture.routeGate.currentRoute, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<_Fixture> _mount(
  WidgetTester tester, {
  bool replacementHasDistinctNote = true,
}) async {
  // Both provider queues must be created in the same real async zone used
  // for seeding. A second queue created in fake time can wait for an unpumped
  // predecessor while runAsync is awaiting its initial write.
  final fixture = (await tester.runAsync(
    () async =>
        _Fixture(previousStore: SharedPreferencesStorePlatform.instance),
  ))!;
  SharedPreferencesStorePlatform.instance = fixture.store;
  await tester.runAsync(() async {
    await fixture.oldProvider.addOrUpdateNotePersisted(
      _note('Old provider note\nold body'),
    );
    if (replacementHasDistinctNote) {
      await fixture.replacementProvider.addOrUpdateNotePersisted(
        _note('Replacement provider note\nnew body'),
      );
    } else {
      await fixture.replacementProvider.addOrUpdateNotePersisted(
        _note('Old provider note\nold body'),
      );
    }
  });
  await tester.runAsync(_loadNoteFonts);
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(() async {
    fixture.store.releaseNoteWrite();
    await _drainWrites(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.routeGate.dispose();
    fixture.oldProvider.dispose();
    fixture.replacementProvider.dispose();
    fixture.activeProvider.dispose();
    fixture.lock.dispose();
    tester.view.reset();
    SharedPreferencesStorePlatform.instance = fixture.previousStore;
  });

  await tester.pumpWidget(_buildApp(fixture));
  await _settleFrames(tester);
  return fixture;
}

Widget _buildApp(_Fixture fixture) => ValueListenableBuilder<NoteProvider>(
  valueListenable: fixture.activeProvider,
  builder: (context, provider, child) => MultiProvider(
    providers: [
      ChangeNotifierProvider<NoteProvider>.value(value: provider),
      ChangeNotifierProvider<AppLockProvider>.value(value: fixture.lock),
    ],
    child: MaterialApp(
      key: fixture.materialAppKey,
      navigatorKey: fixture.navigator,
      navigatorObservers: fixture.navigatorObservers,
      theme: AppBrands.defaultBrand.theme,
      home: const NoteScreen(),
    ),
  ),
);

Future<void> _selectPin(WidgetTester tester) async {
  await tester.tap(find.byTooltip(I18n.tr('note.more')));
  await _settleFrames(tester);
  await tester.tap(find.text(I18n.tr('note.pin')));
  await tester.pump();
}

// Keep the actual private enum value/callback together; widening its generic
// type would introduce a runtime callback cast unrelated to origin protection.
VoidCallback _retainPin(WidgetTester tester, Finder card) {
  final finder = find.descendant(
    of: card,
    matching: find.byWidgetPredicate((widget) => widget is PopupMenuButton),
  );
  final dynamic menu = tester.widget(finder);
  final Iterable<dynamic> entries = menu.itemBuilder(tester.element(finder));
  final dynamic pin = entries.firstWhere(
    (entry) =>
        entry is PopupMenuItem &&
        entry.value.toString().split('.').last == 'pin',
  );
  final dynamic selected = menu.onSelected;
  return () => selected(pin.value);
}

// Busy indicators keep ticking, so route transitions use finite frame pumps.
Future<void> _settleFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pump();
}

Future<void> _waitForHeldWrite(WidgetTester tester, _Store store) async {
  for (var attempt = 0; attempt < 10; attempt++) {
    if (store.noteWriteStarted.isCompleted) return;
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  expect(store.noteWriteStarted.isCompleted, isTrue, reason: 'pin write began');
}

Future<void> _drainWrites(WidgetTester tester) async {
  var drained = false;
  unawaited(AccountPreferenceWrites.drain().then((_) => drained = true));
  for (var attempt = 0; attempt < 100 && !drained; attempt++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
  }
  await tester.pump();
  expect(drained, isTrue, reason: 'bounded preference write drain');
}

Future<void> _pumpFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 40));
  await tester.pump();
}

NoteItem _note(String content) {
  final timestamp = DateTime.utc(2026, 10, 15, 12);
  return NoteItem(
    id: 'shared-note',
    content: content,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

List<NoteItem> _storedNotes(SharedPreferences prefs) =>
    (prefs.getStringList(_notesKey) ?? [])
        .map(
          (raw) => NoteItem.fromJson(jsonDecode(raw) as Map<String, dynamic>),
        )
        .toList();

NoteItem? _storedNote(SharedPreferences prefs, String id) {
  for (final note in _storedNotes(prefs)) {
    if (note.id == id) return note;
  }
  return null;
}

class _Fixture {
  _Fixture({required this.previousStore});

  final SharedPreferencesStorePlatform previousStore;
  final NoteProvider oldProvider = NoteProvider();
  final NoteProvider replacementProvider = NoteProvider();
  late final ValueNotifier<NoteProvider> activeProvider =
      ValueNotifier<NoteProvider>(oldProvider);
  final _TestLock lock = _TestLock();
  final AppAccessRouteGate routeGate = AppAccessRouteGate();
  final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
  final GlobalKey materialAppKey = GlobalKey();
  late final List<NavigatorObserver> navigatorObservers = [routeGate];
  final _Store store = _Store();
}

class _TestLock extends AppLockProvider {
  bool _locked = false;
  int _generation = 0;

  @override
  bool get isLocked => _locked;

  @override
  int get accessGeneration => _generation;

  void setLocked(bool value) {
    if (_locked == value) return;
    _locked = value;
    _generation++;
    notifyListeners();
  }
}

class _Store extends InMemorySharedPreferencesStore {
  _Store() : super.withData(<String, Object>{});

  int noteWriteAttempts = 0;
  bool failNextNoteWrite = false;
  bool _holdNextNoteWrite = false;
  Completer<void> noteWriteStarted = Completer<void>();
  Completer<void> noteWriteRelease = Completer<void>();

  void holdNextNoteWrite() {
    _holdNextNoteWrite = true;
    noteWriteStarted = Completer<void>();
    noteWriteRelease = Completer<void>();
  }

  void releaseNoteWrite() {
    if (!noteWriteRelease.isCompleted) noteWriteRelease.complete();
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key != _platformNotesKey) return super.setValue(type, key, value);
    noteWriteAttempts++;
    if (_holdNextNoteWrite) {
      _holdNextNoteWrite = false;
      noteWriteStarted.complete();
      await noteWriteRelease.future;
    }

    // Simulate a platform that stores the value before reporting a failure;
    // the preference transaction must restore the prior snapshot.
    final saved = await super.setValue(type, key, value);
    if (failNextNoteWrite) {
      failNextNoteWrite = false;
      return false;
    }
    return saved;
  }
}

Future<void> _loadNoteFonts() async {
  await loadWidgetPolishScreenshotFonts();
  final latin = ByteData.sublistView(
    File('assets/fonts/DejaVuSans.ttf').readAsBytesSync(),
  );
  for (final family in ['sans-serif', 'DejaVu Sans', 'Roboto']) {
    await (FontLoader(family)..addFont(Future.value(latin))).load();
  }
  final chinese = ByteData.sublistView(
    File('assets/fonts/DroidSansFallbackFull.ttf').readAsBytesSync(),
  );
  for (final family in const [
    'PingFang SC',
    'Hiragino Sans GB',
    'Noto Sans CJK SC',
    'Source Han Sans SC',
    'Microsoft YaHei',
    'WenQuanYi Micro Hei',
    'DroidSansFallbackFull',
  ]) {
    await (FontLoader(family)..addFont(Future.value(chinese))).load();
  }
  await PaintingBinding.instance.handleSystemMessage(<String, dynamic>{
    'type': 'fontsChange',
  });
}
