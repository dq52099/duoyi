// ignore_for_file: depend_on_referenced_packages

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/notification_ui_copy.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/integrations_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    I18n.setLocale(AppLocale.zh);
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'language tab reports a rejected save and Retry persists English',
    (tester) async {
      SharedPreferences.setMockInitialValues({'duoyi_locale_v1': 'zh'});
      final store = _RejectFirstLocaleWriteStore({
        'flutter.duoyi_locale_v1': 'zh',
      });
      SharedPreferencesStorePlatform.instance = store;

      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final theme = ThemeProvider();
      await theme.loadFromStorage();
      final locale = LocaleProvider();
      await locale.loadFromStorage();
      addTearDown(theme.dispose);
      addTearDown(locale.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeProvider>.value(value: theme),
            ChangeNotifierProvider<LocaleProvider>.value(value: locale),
          ],
          child: MaterialApp(
            theme: theme.brand.theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
            // IntegrationsScreen supplies its optional service providers in a
            // scoped fallback; the explicit LocaleProvider here owns the save.
            home: const IntegrationsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.text(NotificationUiCopy.tabLanguage));
      await tester.tap(find.text(NotificationUiCopy.tabLanguage));
      await tester.pumpAndSettle();
      expect(find.text(I18n.tr('settings.language')), findsOneWidget);
      expect(locale.locale, AppLocale.zh);

      await tester.tap(find.text(I18n.tr('settings.language.en')));
      await tester.pumpAndSettle();
      expect(locale.locale, AppLocale.en);
      expect(I18n.current, AppLocale.en);
      expect(find.text('Display language'), findsOneWidget);
      expect(find.text(NotificationUiCopy.localeSaveFailed), findsOneWidget);
      expect(find.text(I18n.tr('action.retry')), findsOneWidget);
      expect(store.localeWrites, ['en']);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text(I18n.tr('action.retry')));
      await tester.pumpAndSettle();
      expect(locale.locale, AppLocale.en);
      expect(I18n.current, AppLocale.en);
      expect(store.localeWrites, ['en', 'en']);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('duoyi_locale_v1'), 'en');
      expect((await store.getAll())['flutter.duoyi_locale_v1'], 'en');
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}

class _RejectFirstLocaleWriteStore extends InMemorySharedPreferencesStore {
  _RejectFirstLocaleWriteStore(super.data) : super.withData();

  bool _rejectNextLocaleWrite = true;
  final localeWrites = <String>[];

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == 'flutter.duoyi_locale_v1') {
      localeWrites.add(value.toString());
      if (_rejectNextLocaleWrite) {
        _rejectNextLocaleWrite = false;
        return false;
      }
    }
    return super.setValue(valueType, key, value);
  }
}
