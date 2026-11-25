import 'dart:io';

// Promoted after host-reviewed complete-suite and serial timezone acceptance.
// ignore_for_file: depend_on_referenced_packages

import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/core/data_settings_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/backup_screen.dart';
import 'package:duoyi/services/webdav_backup_service.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../support/retained_feedback_visual.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // The service's shared completed Future must belong to the real async
    // zone, so subsequent widget tests do not await a finished fakeAsync zone.
    SharedPreferences.setMockInitialValues({});
    await WebDavBackupService.loadConfig();
  });
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final fails in [false, true]) {
      testWidgets(
        '$brand retained clipboard ${fails ? 'failure' : 'success'} follows locale without recopying content',
        (tester) async {
          final fixture = _Fixture(brand)..clipboardFails = fails;
          try {
            await fixture.mount(tester);
            final export = find.widgetWithText(
              ActionChip,
              DataSettingsUiCopy.exportChipTodoCsv,
            );
            await _reveal(tester, export);
            await tester.tap(export);
            await tester.pumpAndSettle();
            final copy = find.widgetWithText(
              TextButton,
              DataSettingsUiCopy.copyButton,
            );
            await _reveal(tester, copy);
            final exported = tester
                .widget<SelectableText>(find.byType(SelectableText))
                .data!;
            expect(exported, contains('Synthetic 用户任务'));
            await tester.tap(copy);
            await tester.pumpAndSettle();
            expect(fixture.clipboardWrites, 1);
            expect(fixture.copiedText, exported);
            await _expectRetained(
              tester,
              fixture,
              () => fails
                  ? (I18n.current == AppLocale.en
                        ? 'Failed to copy to clipboard. Please try again.'
                        : '复制到剪贴板失败，请重试')
                  : DataSettingsUiCopy.copiedToClipboard,
              caseName: 'clipboard-${fails ? 'failure' : 'success'}',
              verify: () {
                expect(fixture.clipboardWrites, 1);
                expect(fixture.copiedText, exported);
                expect(
                  tester
                      .widget<SelectableText>(find.byType(SelectableText))
                      .data,
                  exported,
                );
                expect(fixture.todos.todos.single.title, 'Synthetic 用户任务');
              },
            );
            expect(fixture.store.mutations, 0);
          } finally {
            await fixture.close(tester);
          }
        },
      );

      testWidgets(
        '$brand retained WebDAV local configuration ${fails ? 'rejection' : 'success'} follows locale without repeating writes',
        (tester) async {
          final fixture = _Fixture(brand)..store.rejectNextConfigWrite = fails;
          try {
            await fixture.mount(tester);
            final configure = find.widgetWithText(
              OutlinedButton,
              DataSettingsUiCopy.webDavConfigureButton(false),
            );
            await _reveal(tester, configure);
            // The service serializes saves through a static Future. Keep the
            // whole dialog continuation in the real zone across widget tests.
            await tester.runAsync(() => tester.tap(configure));
            await tester.pumpAndSettle();
            await tester.enterText(
              find.widgetWithText(TextField, 'WebDAV URL'),
              'https://synthetic.example.test/dav',
            );
            await tester.enterText(
              find.widgetWithText(TextField, DataSettingsUiCopy.webDavUsername),
              'Synthetic 用户',
            );
            await tester.enterText(
              find.widgetWithText(TextField, DataSettingsUiCopy.webDavPassword),
              'synthetic-password',
            );
            await tester.runAsync(() async {
              await tester.tap(
                find.widgetWithText(FilledButton, I18n.tr('action.save')),
              );
              await Future<void>.delayed(Duration.zero);
              await AccountPreferenceWrites.drain();
            });
            await tester.pumpAndSettle();
            final completedState = await fixture.store.getAll();
            expect(completedState['flutter.unrelated_sentinel'], 'keep');
            expect(
              completedState['flutter.webdav_backup_base_url'],
              fails ? isNull : 'https://synthetic.example.test/dav',
            );
            expect(
              completedState['flutter.webdav_backup_username'],
              fails ? isNull : 'Synthetic 用户',
            );
            expect(
              completedState['flutter.webdav_backup_password'],
              fails ? isNull : 'synthetic-password',
            );
            await _expectRetained(
              tester,
              fixture,
              () => fails
                  ? DataSettingsUiCopy.formatWebDavSaveError(
                      StateError('Preference persistence failed'),
                    )
                  : DataSettingsUiCopy.webDavConfigSaved,
              caseName: 'webdav-config-${fails ? 'rejection' : 'success'}',
              verify: () {
                expect(fixture.clipboardWrites, 0);
                expect(find.textContaining('synthetic-password'), findsNothing);
              },
            );
            expect(await fixture.store.getAll(), completedState);
          } finally {
            await fixture.close(tester);
          }
        },
      );
    }
  }
}

Future<void> _expectRetained(
  WidgetTester tester,
  _Fixture fixture,
  String Function() message, {
  required String caseName,
  required VoidCallback verify,
}) async {
  final snack = find.byType(SnackBar);
  expect(snack, findsOneWidget);
  final retainedSnack = tester.element(snack);
  final retainedState = tester.state(find.byType(BackupScreen));
  final mutations = fixture.store.mutations;
  expect(
    find.descendant(of: snack, matching: find.text(message())),
    findsOneWidget,
  );
  for (final next in [AppLocale.en, AppLocale.zh]) {
    I18n.setLocale(next);
    await tester.pump();
    expect(tester.element(snack), same(retainedSnack));
    expect(tester.state(find.byType(BackupScreen)), same(retainedState));
    expect(
      find.descendant(of: snack, matching: find.text(message())),
      findsOneWidget,
    );
    await verifyRetainedFeedbackVisual(
      tester,
      screen: 'backup',
      brand: fixture.brand,
      caseName: caseName,
      message: message(),
    );
    expect(fixture.store.mutations, mutations);
    verify();
    expect(tester.takeException(), isNull);
  }
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    300,
    maxScrolls: 40,
    scrollable: find
        .byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        )
        .first,
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
}

class _Fixture {
  _Fixture(this.brand) : store = _Store(brand);
  final String brand;
  final previousStore = SharedPreferencesStorePlatform.instance;
  final _Store store;
  late final ThemeProvider theme;
  final todos = _Todos();
  bool clipboardFails = false;
  int clipboardWrites = 0;
  String? copiedText;

  Future<void> mount(WidgetTester tester) async {
    if (Platform.environment['DUOYI_CAPTURE_RETAINED_FEEDBACK'] == '1') {
      await tester.runAsync(loadRetainedFeedbackFonts);
    }
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      SharedPreferencesStorePlatform.instance = store;
      await SharedPreferences.getInstance();
      theme = ThemeProvider();
      await theme.loadFromStorage();
    });
    expect(theme.brand.id, brand);
    I18n.setLocale(AppLocale.zh);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardWrites++;
            copiedText = (call.arguments as Map)['text'] as String;
            if (clipboardFails) {
              throw PlatformException(
                code: 'synthetic-copy-failure',
                message: 'synthetic-private diagnostic',
              );
            }
          }
          return null;
        });
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>.value(value: theme),
          ChangeNotifierProvider<TodoProvider>.value(value: todos),
        ],
        child: MaterialApp(
          theme: theme.brand.theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.6)),
            child: RepaintBoundary(
              key: retainedFeedbackCaptureKey,
              child: child!,
            ),
          ),
          home: const BrandRouteSurface(child: BackupScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.runAsync(AccountPreferenceWrites.drain);
    theme.dispose();
    todos.dispose();
    tester.view.reset();
    I18n.setLocale(AppLocale.zh);
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = previousStore;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  }
}

class _Todos extends TodoProvider {
  final items = [TodoItem(id: 'synthetic-task', title: 'Synthetic 用户任务')];
  @override
  List<TodoItem> get todos => items;
}

class _Store extends InMemorySharedPreferencesStore {
  _Store(String brand)
    : super.withData({
        'flutter.active_brand': brand,
        'flutter.unrelated_sentinel': 'keep',
      });
  int mutations = 0;
  bool rejectNextConfigWrite = false;
  @override
  Future<bool> setValue(String type, String key, Object value) {
    mutations++;
    if (rejectNextConfigWrite && key.startsWith('flutter.webdav_backup_')) {
      rejectNextConfigWrite = false;
      return Future.value(false);
    }
    return super.setValue(type, key, value);
  }

  @override
  Future<bool> remove(String key) {
    mutations++;
    return super.remove(key);
  }

  @override
  Future<bool> clear() {
    mutations++;
    return super.clear();
  }
}
