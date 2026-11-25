// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/date_item_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/countdown.dart';
import 'package:duoyi/providers/countdown_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/countdown_screen.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.zh);
  });
  tearDown(() async {
    await AccountPreferenceWrites.drain();
    I18n.setLocale(AppLocale.zh);
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('new category uses a live default hint and keeps the draft', (
    tester,
  ) async {
    final provider = CountdownProvider();
    addTearDown(provider.dispose);
    await _pump(tester, provider);
    final state = tester.state(find.byType(CountdownScreen));
    await tester.tap(find.byKey(const ValueKey('countdown_add_button')));
    await tester.pumpAndSettle();
    final category = _categoryField();
    final controller = tester.widget<TextField>(category).controller!;
    expect(controller.text, isEmpty);
    expect(
      tester.widget<TextField>(category).decoration!.hintText,
      I18n.tr('countdown.category.default'),
    );
    final title = tester
        .widget<TextField>(find.byType(TextField).first)
        .controller!;
    title.text = '用户未保存的标题';
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    title.selection = const TextSelection.collapsed(offset: 3);
    final focus = FocusManager.instance.primaryFocus;
    for (final locale in [AppLocale.en, AppLocale.zh]) {
      I18n.setLocale(locale);
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(CountdownScreen)), same(state));
      expect(tester.widget<TextField>(category).controller, same(controller));
      expect(controller.text, isEmpty);
      expect(
        tester.widget<TextField>(category).decoration!.hintText,
        I18n.tr('countdown.category.default'),
      );
      expect(title.text, '用户未保存的标题');
      expect(title.selection.baseOffset, 3);
      expect(FocusManager.instance.primaryFocus, same(focus));
      expect(provider.items, isEmpty);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('blank category save is locale neutral', (tester) async {
    I18n.setLocale(AppLocale.en);
    final provider = CountdownProvider();
    addTearDown(provider.dispose);
    await _pump(tester, provider);
    await tester.tap(find.byKey(const ValueKey('countdown_add_button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '版本发布');
    await tester.enterText(_categoryField(), '');
    await tester.tap(
      find.byKey(const ValueKey('countdown_editor_save_button')),
    );
    await tester.pumpAndSettle();
    expect(provider.items.single.category, '默认');
    expect(provider.items.single.categoryIsDefault, isTrue);
    final stored = (await SharedPreferences.getInstance()).getStringList(
      'duoyi_countdowns',
    );
    final before = jsonEncode(provider.items.single.toJson());
    I18n.setLocale(AppLocale.zh);
    await tester.pumpAndSettle();
    expect(jsonEncode(provider.items.single.toJson()), before);
    expect(
      (await SharedPreferences.getInstance()).getStringList('duoyi_countdowns'),
      stored,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final authored in [false, true]) {
    testWidgets('card localizes generated category only authored=$authored', (
      tester,
    ) async {
      final provider = CountdownProvider();
      addTearDown(provider.dispose);
      final item = authored
          ? CountdownItem(
              id: 'category',
              title: '用户标题',
              targetDate: DateTime(2099, 7, 1),
              category: '默认',
            )
          : CountdownItem(
              id: 'category',
              title: '用户标题',
              targetDate: DateTime(2099, 7, 1),
            );
      await provider.addItem(item);
      await _pump(tester, provider);
      final before = jsonEncode(provider.items.single.toJson());
      final card = find.byKey(const ValueKey('countdown_card_category'));
      for (final locale in [AppLocale.zh, AppLocale.en, AppLocale.zh]) {
        I18n.setLocale(locale);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          card,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          find.descendant(
            of: card,
            matching: find.text(
              authored ? '默认' : I18n.tr('countdown.category.default'),
            ),
          ),
          findsOneWidget,
        );
        expect(jsonEncode(provider.items.single.toJson()), before);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final category in ['默认', 'Default', '自定义分类']) {
    testWidgets('explicit $category stays custom until reset', (tester) async {
      final provider = CountdownProvider();
      addTearDown(provider.dispose);
      await provider.addItem(
        CountdownItem(
          id: 'edit',
          title: 'User title',
          targetDate: DateTime(2099, 7, 1),
          category: category,
        ),
      );
      await _pump(tester, provider, initialCountdownId: 'edit');
      final controller = tester.widget<TextField>(_categoryField()).controller!;
      expect(controller.text, category);
      final before = jsonEncode(provider.items.single.toJson());
      for (final locale in [AppLocale.en, AppLocale.zh]) {
        I18n.setLocale(locale);
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(_categoryField()).controller,
          same(controller),
        );
        expect(controller.text, category);
        expect(
          find.byKey(const ValueKey('countdown_editor_save_button')),
          findsOneWidget,
        );
        expect(jsonEncode(provider.items.single.toJson()), before);
        expect(find.byTooltip(DateItemUiCopy.resetCategory), findsOneWidget);
      }
      await tester.tap(find.byKey(const ValueKey('countdown_category_reset')));
      await tester.pumpAndSettle();
      expect(controller.text, isEmpty);
      expect(
        tester.widget<TextField>(_categoryField()).decoration!.hintText,
        I18n.tr('countdown.category.default'),
      );
      await tester.tap(
        find.byKey(const ValueKey('countdown_editor_save_button')),
      );
      await tester.pumpAndSettle();
      final reload = CountdownProvider();
      addTearDown(reload.dispose);
      await reload.loadFromStorage();
      expect(reload.items.single.categoryIsDefault, isTrue);
      expect(reload.items.single.category, CountdownItem.defaultCategory);
      expect(reload.items.single.title, 'User title');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final custom in [false, true]) {
    testWidgets(
      'failed save keeps category provenance across retry custom=$custom',
      (tester) async {
        final store = _CategoryStore();
        SharedPreferencesStorePlatform.instance = store;
        final provider = CountdownProvider();
        addTearDown(provider.dispose);
        await _pump(tester, provider);
        await tester.tap(find.byKey(const ValueKey('countdown_add_button')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, 'Retry title');
        if (custom) await tester.enterText(_categoryField(), '默认');
        store.rejectNext = true;
        await tester.tap(
          find.byKey(const ValueKey('countdown_editor_save_button')),
        );
        await tester.pumpAndSettle();
        expect(provider.items, isEmpty);
        expect(find.text(DateItemUiCopy.saveFailed), findsOneWidget);
        I18n.setLocale(AppLocale.en);
        await tester.pumpAndSettle();
        expect(find.text(DateItemUiCopy.saveFailed), findsOneWidget);
        expect(
          tester.widget<TextField>(_categoryField()).controller!.text,
          custom ? '默认' : '',
        );
        final retry = find.text(I18n.tr('action.retry'));
        await tester.ensureVisible(retry);
        await tester.tap(retry);
        await tester.pumpAndSettle();
        expect(provider.items.single.categoryIsDefault, !custom);
        expect(provider.items.single.category, '默认');
        final reload = CountdownProvider();
        addTearDown(reload.dispose);
        await reload.loadFromStorage();
        expect(reload.items.single.categoryIsDefault, !custom);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'locale change during persistence leaves pending default canonical',
    (tester) async {
      final store = _CategoryStore()..release = Completer<void>();
      addTearDown(() {
        if (!store.release!.isCompleted) store.release!.complete();
      });
      SharedPreferencesStorePlatform.instance = store;
      final provider = CountdownProvider();
      addTearDown(provider.dispose);
      await _pump(tester, provider);
      await tester.tap(find.byKey(const ValueKey('countdown_add_button')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Pending title');
      await tester.tap(
        find.byKey(const ValueKey('countdown_editor_save_button')),
      );
      await tester.pump();
      await tester.runAsync(() => store.started.future);
      I18n.setLocale(AppLocale.en);
      await tester.pump();
      expect(provider.items, isEmpty);
      expect(
        tester.widget<TextField>(_categoryField()).controller!.text,
        isEmpty,
      );
      store.release!.complete();
      await tester.pumpAndSettle();
      expect(provider.items.single.categoryIsDefault, isTrue);
      expect(provider.items.single.category, CountdownItem.defaultCategory);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('opened date picker refreshes title and retains editor draft', (
    tester,
  ) async {
    final previousHitTestPolicy = WidgetController.hitTestWarningShouldBeFatal;
    WidgetController.hitTestWarningShouldBeFatal = true;
    addTearDown(
      () =>
          WidgetController.hitTestWarningShouldBeFatal = previousHitTestPolicy,
    );
    final provider = CountdownProvider();
    addTearDown(provider.dispose);
    await _pump(tester, provider);
    final screenState = tester.state(find.byType(CountdownScreen));
    await tester.tap(find.byKey(const ValueKey('countdown_add_button')));
    await tester.pumpAndSettle();
    final title = tester
        .widget<TextField>(find.byType(TextField).first)
        .controller!;
    title.text = 'Date picker draft';
    await tester.tap(find.text(I18n.tr('countdown.field.target_date')));
    await tester.pumpAndSettle();
    for (final locale in [AppLocale.en, AppLocale.zh]) {
      I18n.setLocale(locale);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AppModalSheet).last,
          matching: find.text(I18n.tr('countdown.field.target_date')),
        ),
        findsOneWidget,
      );
      expect(tester.state(find.byType(CountdownScreen)), same(screenState));
      expect(title.text, 'Date picker draft');
      expect(tester.takeException(), isNull);
    }
    expect(find.byType(AppModalSheet), findsNWidgets(2));
    final cancel = find.descendant(
      of: find.byType(AppModalSheet).last,
      matching: find.text(I18n.tr('action.cancel')),
    );
    await tester.ensureVisible(cancel);
    await tester.pumpAndSettle();
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(find.byType(AppModalSheet), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller,
      same(title),
    );
    expect(title.text, 'Date picker draft');
    expect(provider.items, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Finder _categoryField() => find.byWidgetPredicate(
  (widget) =>
      widget is TextField &&
      widget.decoration?.labelText == I18n.tr('countdown.field.category'),
);

Future<void> _pump(
  WidgetTester tester,
  CountdownProvider provider, {
  String? initialCountdownId,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: provider),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: MaterialApp(
        home: BrandRouteSurface(
          child: CountdownScreen(initialCountdownId: initialCountdownId),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _CategoryStore extends InMemorySharedPreferencesStore {
  _CategoryStore() : super.withData({});
  bool rejectNext = false;
  Completer<void>? release;
  final started = Completer<void>();

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == 'flutter.duoyi_countdowns') {
      if (release != null && !started.isCompleted) {
        started.complete();
        await release!.future;
      }
      if (rejectNext) {
        rejectNext = false;
        return false;
      }
    }
    return super.setValue(type, key, value);
  }
}
