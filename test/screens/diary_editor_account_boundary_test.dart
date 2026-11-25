// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/local_timezone_resolver.dart';
import 'package:duoyi/core/recommended_goals_ui_copy.dart';
import 'package:duoyi/models/diary_entry.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/providers/preferences_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/diary_screen.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';

class _RecordingPreferencesStore extends InMemorySharedPreferencesStore {
  _RecordingPreferencesStore(super.data) : super.withData();

  int diaryWrites = 0;
  int tombstoneWrites = 0;

  static bool _isDiaryKey(String key) =>
      key == 'duoyi_diary' ||
      key == 'flutter.duoyi_diary' ||
      key.endsWith('.duoyi_diary');

  static bool _isTombstoneKey(String key) =>
      key == 'sync_deleted_items' ||
      key == 'flutter.sync_deleted_items' ||
      key.endsWith('.sync_deleted_items');

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    if (_isDiaryKey(key)) {
      diaryWrites++;
    }
    if (_isTombstoneKey(key)) {
      tombstoneWrites++;
    }
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) {
    if (_isDiaryKey(key)) {
      diaryWrites++;
    }
    if (_isTombstoneKey(key)) {
      tombstoneWrites++;
    }
    return super.remove(key);
  }
}

class _RecordingDiaryProvider extends DiaryProvider {
  int addOrUpdateCalls = 0;
  int deleteCalls = 0;

  @override
  Future<void> addOrUpdate(DiaryEntry entry) async {
    addOrUpdateCalls++;
    await super.addOrUpdate(entry);
  }

  @override
  Future<void> delete(String id) async {
    deleteCalls++;
    await super.delete(id);
  }
}

class _MutableAuthProvider extends AuthProvider {
  _MutableAuthProvider({super.initialState});

  int _generation = 0;

  @override
  int get sessionGeneration => _generation;

  void triggerSessionChange() {
    _generation++;
    notifyListeners();
  }
}

Future<void> _mountAndPushEditor({
  required WidgetTester tester,
  required GlobalKey<NavigatorState> navigatorKey,
  required DiaryProvider diaries,
  ThemeProvider? theme,
  PreferencesProvider? preferences,
  AuthProvider? auth,
  ThemeData? themeData,
  DiaryEntry? entry,
  DateTime? initialDate,
}) async {
  tester.view.physicalSize = const Size(800, 1200);
  tester.view.devicePixelRatio = 1.0;

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<DiaryProvider>.value(value: diaries),
        if (theme != null)
          ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        if (preferences != null)
          ChangeNotifierProvider<PreferencesProvider>.value(value: preferences),
        if (auth != null)
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        theme: themeData ?? theme?.brand.theme,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('en'), Locale('zh')],
        home: const Scaffold(
          body: Center(child: Text('Root Anchor Screen')),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  navigatorKey.currentState!.push<void>(
    MaterialPageRoute(
      builder: (_) => DiaryEditScreen(
        entry: entry,
        initialDate: initialDate,
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.byType(DiaryEditScreen), findsOneWidget);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final initialGlobalLocale = I18n.current;
  final initialTimezoneReader =
      LocalTimezoneResolver.debugSystemTimeZoneReader;

  setUp(() {
    LocalTimezoneResolver.debugSystemTimeZoneReader =
        () async => 'Asia/Shanghai';
  });

  tearDown(() {
    LocalTimezoneResolver.debugSystemTimeZoneReader = initialTimezoneReader;
    I18n.setLocale(initialGlobalLocale);
  });

  const priorityBrandIds = <String>['defaultBrand', 'liquidGlass'];

  for (final brandId in priorityBrandIds) {
    group('Priority theme $brandId stale save closure rejection', () {
      testWidgets(
        'Stale save closure rejected after global account invalidation and provider reset',
        (tester) async {
          addTearDown(() => tester.view.resetPhysicalSize());
          final initialPrefs = <String, Object>{
            'duoyi_diary': <String>[],
            'flutter.duoyi_diary': <String>[],
            'flutter.active_brand': brandId,
            'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
            'flutter.theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
          };
          SharedPreferences.setMockInitialValues(initialPrefs);
          final store = _RecordingPreferencesStore({
            for (final entry in initialPrefs.entries)
              if (!entry.key.startsWith('flutter.'))
                'flutter.${entry.key}': entry.value,
          });
          SharedPreferencesStorePlatform.instance = store;

          final diaries = _RecordingDiaryProvider();
          final theme = ThemeProvider();
          final preferences = PreferencesProvider();
          await diaries.loadFromStorage();
          await preferences.loadFromStorage();

          int mutationCallbacks = 0;
          diaries.onLocalMutationPersisted = () => mutationCallbacks++;

          final brand = AppBrands.byId(brandId);
          final navigatorKey = GlobalKey<NavigatorState>();

          await _mountAndPushEditor(
            tester: tester,
            navigatorKey: navigatorKey,
            diaries: diaries,
            theme: theme,
            preferences: preferences,
            themeData: brand.theme,
            initialDate: DateTime(2026, 10, 24),
          );

          final contentField = find.byWidgetPredicate(
            (w) => w is TextField && w.maxLines == 12,
          );
          expect(contentField, findsOneWidget);
          await tester.enterText(contentField, 'Draft for prior account');
          await tester.pumpAndSettle();

          final checkButton = find.widgetWithIcon(IconButton, Icons.check);
          expect(checkButton, findsOneWidget);
          final staleSaveClosure =
              tester.widget<IconButton>(checkButton).onPressed;
          expect(staleSaveClosure, isNotNull);

          final writesBefore = store.diaryWrites;

          // Invalidate global account and reset provider
          AccountLocalDataCleaner.invalidateInFlightAccountWrites();
          diaries.resetLocalState();
          await tester.pump();

          // Explicitly invoke the saved old closure FIRST
          staleSaveClosure!();
          await tester.pumpAndSettle();

          // Assert boundary invariants:
          expect(diaries.addOrUpdateCalls, equals(0));
          expect(diaries.entries, isEmpty);
          expect(store.diaryWrites, equals(writesBefore));
          final prefs = await SharedPreferences.getInstance();
          final storedDiaries = prefs.getStringList('duoyi_diary') ?? [];
          expect(storedDiaries, isEmpty);
          expect(mutationCallbacks, equals(0));
          expect(find.byType(DiaryEditScreen), findsOneWidget);
          expect(find.text(RecommendedGoalsUiCopy.expired), findsOneWidget);
          expect(find.text('Draft for prior account'), findsNothing);
          expect(
            tester
                .widget<IconButton>(
                  find.widgetWithIcon(IconButton, Icons.check),
                )
                .onPressed,
            isNull,
          );
        },
      );
    });
  }

  for (final brandId in priorityBrandIds) {
    group('Priority theme $brandId stale empty draft delete rejection', () {
      testWidgets(
        'Stale empty draft delete closure cannot call delete or write old ID tombstone',
        (tester) async {
          addTearDown(() => tester.view.resetPhysicalSize());
          const existingId = 'existing-diary-id-8899';
          const unrelatedCollection = 'unrelated_coll';
          const unrelatedId = 'unrelated-tombstone-999';
          const unrelatedStamp = '2026-10-24T12:00:00.000Z';

          final existingEntry = DiaryEntry(
            id: existingId,
            date: DateTime(2026, 10, 24),
            content: 'Existing diary to be deleted',
          );
          final initialDeletedItemsJson = jsonEncode({
            unrelatedCollection: {unrelatedId: unrelatedStamp},
          });

          final initialPrefs = <String, Object>{
            'duoyi_diary': <String>[jsonEncode(existingEntry.toJson())],
            'flutter.duoyi_diary': <String>[jsonEncode(existingEntry.toJson())],
            'sync_deleted_items': initialDeletedItemsJson,
            'flutter.sync_deleted_items': initialDeletedItemsJson,
            'flutter.active_brand': brandId,
            'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
            'flutter.theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
          };
          SharedPreferences.setMockInitialValues(initialPrefs);
          final store = _RecordingPreferencesStore({
            for (final entry in initialPrefs.entries)
              if (!entry.key.startsWith('flutter.'))
                'flutter.${entry.key}': entry.value,
          });
          SharedPreferencesStorePlatform.instance = store;

          final diaries = _RecordingDiaryProvider();
          final theme = ThemeProvider();
          final preferences = PreferencesProvider();
          await diaries.loadFromStorage();
          await preferences.loadFromStorage();
          expect(diaries.entries.length, 1);
          expect(diaries.entries.first.id, existingId);

          final brand = AppBrands.byId(brandId);
          final navigatorKey = GlobalKey<NavigatorState>();

          await _mountAndPushEditor(
            tester: tester,
            navigatorKey: navigatorKey,
            diaries: diaries,
            theme: theme,
            preferences: preferences,
            themeData: brand.theme,
            entry: existingEntry,
          );

          // Clear the content so it enters the empty-draft delete branch
          final contentField = find.byWidgetPredicate(
            (w) => w is TextField && w.maxLines == 12,
          );
          await tester.enterText(contentField, '');
          await tester.pumpAndSettle();

          final checkButton = find.widgetWithIcon(IconButton, Icons.check);
          final staleDeleteClosure =
              tester.widget<IconButton>(checkButton).onPressed;
          expect(staleDeleteClosure, isNotNull);

          final tombstoneWritesBefore = store.tombstoneWrites;

          // Invalidate global account and reset provider
          AccountLocalDataCleaner.invalidateInFlightAccountWrites();
          diaries.resetLocalState();
          await tester.pump();

          // Explicitly invoke stale delete closure
          staleDeleteClosure!();
          await tester.pumpAndSettle();

          // Assert boundary invariants:
          expect(diaries.deleteCalls, equals(0));
          expect(store.tombstoneWrites, equals(tombstoneWritesBefore));
          final prefs = await SharedPreferences.getInstance();
          final rawTombstones = prefs.getString('sync_deleted_items');
          expect(rawTombstones, isNotNull);
          final decoded = jsonDecode(rawTombstones!) as Map<String, dynamic>;
          final diaryBucket = decoded['diaries'] as Map<String, dynamic>?;
          expect(diaryBucket?[existingId], isNull);
          final otherBucket =
              decoded[unrelatedCollection] as Map<String, dynamic>?;
          expect(otherBucket?[unrelatedId], equals(unrelatedStamp));
          expect(find.byType(DiaryEditScreen), findsOneWidget);
          expect(find.text(RecommendedGoalsUiCopy.expired), findsOneWidget);
          expect(
            tester
                .widget<IconButton>(
                  find.widgetWithIcon(IconButton, Icons.check),
                )
                .onPressed,
            isNull,
          );
        },
      );
    });
  }

  testWidgets(
    'Auth session event invalidates editor and rejects stale save closure',
    (tester) async {
      addTearDown(() => tester.view.resetPhysicalSize());
      final initialPrefs = <String, Object>{
        'duoyi_diary': <String>[],
        'flutter.duoyi_diary': <String>[],
      };
      SharedPreferences.setMockInitialValues(initialPrefs);
      final store = _RecordingPreferencesStore({
        for (final entry in initialPrefs.entries)
          if (!entry.key.startsWith('flutter.'))
            'flutter.${entry.key}': entry.value,
      });
      SharedPreferencesStorePlatform.instance = store;

      final diaries = _RecordingDiaryProvider();
      await diaries.loadFromStorage();

      final auth = _MutableAuthProvider(
        initialState: const AuthState(
          userId: 'user-auth-101',
          token: 'token-abc',
        ),
      );

      final navigatorKey = GlobalKey<NavigatorState>();
      await _mountAndPushEditor(
        tester: tester,
        navigatorKey: navigatorKey,
        diaries: diaries,
        auth: auth,
        initialDate: DateTime(2026, 10, 24),
      );

      final contentField = find.byWidgetPredicate(
        (w) => w is TextField && w.maxLines == 12,
      );
      await tester.enterText(contentField, 'Auth session boundary text');
      await tester.pumpAndSettle();

      final checkButton = find.widgetWithIcon(IconButton, Icons.check);
      final staleSaveClosure =
          tester.widget<IconButton>(checkButton).onPressed;
      expect(staleSaveClosure, isNotNull);

      // Trigger Auth session generation change
      auth.triggerSessionChange();
      await tester.pump();

      // Invoke stale callback FIRST
      staleSaveClosure!();
      await tester.pumpAndSettle();

      expect(diaries.addOrUpdateCalls, equals(0));
      expect(diaries.entries, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      final storedDiaries = prefs.getStringList('duoyi_diary') ?? [];
      expect(storedDiaries, isEmpty);
      expect(find.byType(DiaryEditScreen), findsOneWidget);
      expect(find.text(RecommendedGoalsUiCopy.expired), findsOneWidget);
      expect(find.text('Auth session boundary text'), findsNothing);
      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.check))
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'Provider replacement in tree invalidates editor and rejects stale save closure',
    (tester) async {
      addTearDown(() => tester.view.resetPhysicalSize());
      final initialPrefs = <String, Object>{
        'duoyi_diary': <String>[],
        'flutter.duoyi_diary': <String>[],
      };
      SharedPreferences.setMockInitialValues(initialPrefs);
      SharedPreferencesStorePlatform.instance =
          _RecordingPreferencesStore({'flutter.duoyi_diary': <String>[]});

      final initialDiaries = _RecordingDiaryProvider();
      final replacementDiaries = _RecordingDiaryProvider();
      await initialDiaries.loadFromStorage();
      await replacementDiaries.loadFromStorage();

      final providerNotifier = ValueNotifier<DiaryProvider>(initialDiaries);
      final navigatorKey = GlobalKey<NavigatorState>();

      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        ValueListenableBuilder<DiaryProvider>(
          valueListenable: providerNotifier,
          builder: (context, currentDiaries, _) {
            return MultiProvider(
              providers: [
                ChangeNotifierProvider<DiaryProvider>.value(
                  value: currentDiaries,
                ),
              ],
              child: MaterialApp(
                navigatorKey: navigatorKey,
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                supportedLocales: const [Locale('en'), Locale('zh')],
                home: const Scaffold(
                  body: Center(child: Text('Root Anchor Screen')),
                ),
              ),
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      navigatorKey.currentState!.push<void>(
        MaterialPageRoute(
          builder: (_) => DiaryEditScreen(
            initialDate: DateTime(2026, 10, 24),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final contentField = find.byWidgetPredicate(
        (w) => w is TextField && w.maxLines == 12,
      );
      await tester.enterText(contentField, 'Provider replacement draft');
      await tester.pumpAndSettle();

      final checkButton = find.widgetWithIcon(IconButton, Icons.check);
      final staleSaveClosure =
          tester.widget<IconButton>(checkButton).onPressed;
      expect(staleSaveClosure, isNotNull);

      // Replace DiaryProvider instance in the tree
      providerNotifier.value = replacementDiaries;
      await tester.pump();

      // Invoke stale closure
      staleSaveClosure!();
      await tester.pumpAndSettle();

      expect(replacementDiaries.addOrUpdateCalls, equals(0));
      expect(replacementDiaries.entries, isEmpty);
      expect(initialDiaries.addOrUpdateCalls, equals(0));
      expect(initialDiaries.entries, isEmpty);
      expect(find.byType(DiaryEditScreen), findsOneWidget);
      expect(find.text(RecommendedGoalsUiCopy.expired), findsOneWidget);
      expect(find.text('Provider replacement draft'), findsNothing);
    },
  );

  testWidgets(
    'Stale save callback cannot pop a newer covering route',
    (tester) async {
      addTearDown(() => tester.view.resetPhysicalSize());
      SharedPreferences.setMockInitialValues({'duoyi_diary': <String>[]});
      final diaries = _RecordingDiaryProvider();
      await diaries.loadFromStorage();

      final navigatorKey = GlobalKey<NavigatorState>();

      await _mountAndPushEditor(
        tester: tester,
        navigatorKey: navigatorKey,
        diaries: diaries,
        initialDate: DateTime(2026, 10, 24),
      );

      final contentField = find.byWidgetPredicate(
        (w) => w is TextField && w.maxLines == 12,
      );
      await tester.enterText(contentField, 'Draft before push');
      await tester.pumpAndSettle();

      final checkButton = find.widgetWithIcon(IconButton, Icons.check);
      final staleSaveClosure =
          tester.widget<IconButton>(checkButton).onPressed;
      expect(staleSaveClosure, isNotNull);

      // Push covering route
      unawaited(
        navigatorKey.currentState!.push<void>(
          MaterialPageRoute(
            builder: (_) => const Scaffold(
              body: Center(child: Text('Newer Covering Route View')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Newer Covering Route View'), findsOneWidget);

      // Stale save closure invoked while covered
      staleSaveClosure!();
      await tester.pumpAndSettle();

      // Covering route must not be popped
      expect(find.text('Newer Covering Route View'), findsOneWidget);
      expect(
        find.byType(DiaryEditScreen, skipOffstage: false),
        findsOneWidget,
      );
      expect(diaries.addOrUpdateCalls, equals(0));
    },
  );

  testWidgets(
    'Valid account positive control: normal save and empty delete succeed and pop',
    (tester) async {
      addTearDown(() => tester.view.resetPhysicalSize());
      SharedPreferences.setMockInitialValues({'duoyi_diary': <String>[]});
      final diaries = _RecordingDiaryProvider();
      await diaries.loadFromStorage();

      final navigatorKey = GlobalKey<NavigatorState>();

      await _mountAndPushEditor(
        tester: tester,
        navigatorKey: navigatorKey,
        diaries: diaries,
        initialDate: DateTime(2026, 10, 24),
      );

      final contentField = find.byWidgetPredicate(
        (w) => w is TextField && w.maxLines == 12,
      );
      await tester.enterText(contentField, 'Valid persistent entry');
      await tester.tap(find.widgetWithIcon(IconButton, Icons.check));
      await tester.pumpAndSettle();

      // Successfully saved and popped back to root anchor screen
      expect(find.byType(DiaryEditScreen), findsNothing);
      expect(find.text('Root Anchor Screen'), findsOneWidget);
      expect(diaries.addOrUpdateCalls, equals(1));
      expect(diaries.entries.length, 1);
      expect(diaries.entries.first.content, 'Valid persistent entry');

      // Now push editor with the saved entry and clear to delete
      final savedEntry = diaries.entries.first;
      navigatorKey.currentState!.push<void>(
        MaterialPageRoute(
          builder: (_) => DiaryEditScreen(entry: savedEntry),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DiaryEditScreen), findsOneWidget);

      final editContentField = find.byWidgetPredicate(
        (w) => w is TextField && w.maxLines == 12,
      );
      await tester.enterText(editContentField, '');
      await tester.tap(find.widgetWithIcon(IconButton, Icons.check));
      await tester.pumpAndSettle();

      // Successfully deleted and popped
      expect(find.byType(DiaryEditScreen), findsNothing);
      expect(find.text('Root Anchor Screen'), findsOneWidget);
      expect(diaries.deleteCalls, equals(1));
      expect(diaries.entries, isEmpty);
    },
  );

  testWidgets(
    'Valid account positive control: draft, mood, weather, tags preserved across theme and locale switch',
    (tester) async {
      addTearDown(() => tester.view.resetPhysicalSize());
      // Explicit initial locale: zh
      I18n.setLocale(AppLocale.zh);

      final baselineDate = DateTime(2026, 10, 24);
      SharedPreferences.setMockInitialValues({
        'duoyi_diary': <String>[],
        'flutter.active_brand': 'defaultBrand',
        'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
        'flutter.theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
      });
      final diaries = _RecordingDiaryProvider();
      final theme = ThemeProvider();
      await diaries.loadFromStorage();
      await theme.loadFromStorage();
      expect(theme.brand.id, equals('defaultBrand'));

      final navigatorKey = GlobalKey<NavigatorState>();

      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<DiaryProvider>.value(value: diaries),
            ChangeNotifierProvider<ThemeProvider>.value(value: theme),
          ],
          child: Consumer<ThemeProvider>(
            builder: (context, currentTheme, _) {
              return ValueListenableBuilder<AppLocale>(
                valueListenable: I18n.localeListenable,
                builder: (context, currentLocale, _) {
                  return MaterialApp(
                    navigatorKey: navigatorKey,
                    locale: currentLocale.flutterLocale,
                    supportedLocales: const [Locale('en'), Locale('zh')],
                    localizationsDelegates:
                        GlobalMaterialLocalizations.delegates,
                    theme: currentTheme.brand.theme,
                    home: const Scaffold(
                      body: Center(child: Text('Root Anchor Screen')),
                    ),
                  );
                },
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      navigatorKey.currentState!.push<void>(
        MaterialPageRoute(
          builder: (_) => DiaryEditScreen(
            initialDate: baselineDate,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DiaryEditScreen), findsOneWidget);

      // Enter draft content
      final contentField = find.byWidgetPredicate(
        (w) => w is TextField && w.maxLines == 12,
      );
      await tester.enterText(contentField, 'Resilient draft content');

      // Select mood
      await tester.tap(find.text(Mood.awesome.emoji));
      await tester.pumpAndSettle();

      // Select weather
      final sunnyFilterChip = find.byWidgetPredicate(
        (w) =>
            w is FilterChip &&
            w.label is Text &&
            (w.label as Text).data!.contains(Weather.sunny.emoji),
      );
      await tester.tap(sunnyFilterChip);
      await tester.pumpAndSettle();

      // Add tag
      final tagField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.prefixIcon is Icon,
      );
      await tester.enterText(tagField, 'vacation');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('vacation'), findsOneWidget);

      // 1. Switch Theme while mounted (defaultBrand -> liquidGlass)
      await theme.setBrand('liquidGlass');
      await tester.pumpAndSettle();
      expect(theme.brand.id, equals('liquidGlass'));

      // Verify draft, mood, weather, tags are fully preserved!
      expect(find.text('Resilient draft content'), findsOneWidget);
      expect(find.text('vacation'), findsOneWidget);
      expect(find.text(Mood.awesome.emoji), findsWidgets);

      // 2. Switch Locale while mounted (zh -> en)
      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      expect(I18n.current, equals(AppLocale.en));

      // Verify draft, mood, weather, tags still fully preserved!
      expect(find.text('Resilient draft content'), findsOneWidget);
      expect(find.text('vacation'), findsOneWidget);
      expect(find.text(Mood.awesome.emoji), findsWidgets);

      // Save under new theme and locale succeeds
      await tester.tap(find.widgetWithIcon(IconButton, Icons.check));
      await tester.pumpAndSettle();

      // Assert popped back to root
      expect(find.byType(DiaryEditScreen), findsNothing);
      expect(find.text('Root Anchor Screen'), findsOneWidget);

      // Assert saved entry has all fields preserved
      expect(diaries.entries.length, 1);
      final saved = diaries.entries.first;
      expect(saved.content, 'Resilient draft content');
      expect(saved.mood, Mood.awesome);
      expect(saved.weather, Weather.sunny);
      expect(saved.tags, ['vacation']);
      expect(saved.date.year, baselineDate.year);
      expect(saved.date.month, baselineDate.month);
      expect(saved.date.day, baselineDate.day);
    },
  );
}
