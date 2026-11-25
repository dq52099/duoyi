import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
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
import 'package:duoyi/providers/user_provider.dart';
import 'package:duoyi/screens/profile_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:duoyi/widgets/account_status_chip.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/weekly_review_screenshot_font.dart';

enum _Host { brandedStandalone, root, profileLocal, profileAccount }

String _label(AccountDisplayStatus status) => switch (status) {
  AccountDisplayStatus.notLoggedIn => AccountUiCopy.statusNotLoggedIn,
  AccountDisplayStatus.loggedIn => AccountUiCopy.statusLoggedIn,
  AccountDisplayStatus.syncing => AccountUiCopy.statusSyncing,
  AccountDisplayStatus.syncFailed => AccountUiCopy.statusSyncFailed,
  AccountDisplayStatus.localOnly => AccountUiCopy.statusLocalMode,
};

const _statuses = Column(
  mainAxisSize: MainAxisSize.min,
  children: [
    AccountStatusChip(status: AccountDisplayStatus.notLoggedIn),
    AccountStatusChip(status: AccountDisplayStatus.loggedIn),
    AccountStatusChip(status: AccountDisplayStatus.syncing),
    AccountStatusChip(status: AccountDisplayStatus.syncFailed),
    AccountStatusChip(status: AccountDisplayStatus.localOnly),
  ],
);

void main() {
  tearDown(() => I18n.setLocale(AppLocale.zh));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final initial in AppLocale.values) {
      for (final host in _Host.values) {
        final name = '$brand-${initial.name}-${host.name}';
        testWidgets('retained account status locale $name', (tester) async {
          SharedPreferences.setMockInitialValues({'active_brand': brand});
          tester.view.physicalSize = const Size(320, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final theme = ThemeProvider();
          late final LocaleProvider locale;
          final transport = MockClient((request) async {
            fail(
              'Unexpected synthetic request: ${request.method} ${request.url.path}',
            );
          });
          final auth = _FixtureAuth(
            ApiClient(
              baseUrl: 'https://synthetic.example.test',
              httpClient: transport,
            ),
            host == _Host.profileAccount,
          );
          final lock = AppLockProvider();
          final updater = _Updater();
          final rewards = AchievementProvider();
          final focus = FocusRoomProvider();
          final pomodoro = PomodoroProvider();
          final todo = TodoProvider();
          final preferences = PreferencesProvider();
          final goal = GoalProvider();
          final user = UserProvider();
          final ai = AiService();
          await tester.runAsync(() async {
            await theme.loadFromStorage();
            locale = LocaleProvider();
            await locale.setLocale(initial);
            await loadWeeklyReviewScreenshotFonts();
          });
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
            for (final provider in <ChangeNotifier>[
              theme,
              locale,
              auth,
              lock,
              updater,
              rewards,
              focus,
              pomodoro,
              todo,
              preferences,
              goal,
              user,
              ai,
            ]) {
              provider.dispose();
            }
            transport.close();
          });
          final capture = GlobalKey();
          final editor =
              host == _Host.profileLocal || host == _Host.profileAccount;
          final screen = editor
              ? const ProfileScreen()
              : const Scaffold(body: Center(child: _statuses));
          final route = BrandRouteSurface(
            remountOnLocaleChange: false,
            child: screen,
          );
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<ThemeProvider>.value(value: theme),
                ChangeNotifierProvider<LocaleProvider>.value(value: locale),
                ChangeNotifierProvider<AuthProvider>.value(value: auth),
                ChangeNotifierProvider<AppLockProvider>.value(value: lock),
                ChangeNotifierProvider<AppUpdateService>.value(value: updater),
                ChangeNotifierProvider<AchievementProvider>.value(
                  value: rewards,
                ),
                ChangeNotifierProvider<FocusRoomProvider>.value(value: focus),
                ChangeNotifierProvider<PomodoroProvider>.value(value: pomodoro),
                ChangeNotifierProvider<TodoProvider>.value(value: todo),
                ChangeNotifierProvider<PreferencesProvider>.value(
                  value: preferences,
                ),
                ChangeNotifierProvider<GoalProvider>.value(value: goal),
                ChangeNotifierProvider<UserProvider>.value(value: user),
                ChangeNotifierProvider<AiService>.value(value: ai),
              ],
              child: RepaintBoundary(
                key: capture,
                child: MediaQuery(
                  data: const MediaQueryData(
                    size: Size(320, 844),
                    textScaler: TextScaler.linear(1.6),
                  ),
                  child: host == _Host.brandedStandalone
                      ? MaterialApp(
                          theme: theme.brand.theme,
                          supportedLocales: const [Locale('en'), Locale('zh')],
                          localizationsDelegates:
                              GlobalMaterialLocalizations.delegates,
                          home: route,
                        )
                      : const DuoyiApp(),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (host != _Host.brandedStandalone) {
            final navigator = tester.state<NavigatorState>(
              find.byType(Navigator).first,
            );
            unawaited(
              navigator.push(MaterialPageRoute<void>(builder: (_) => route)),
            );
            await tester.pumpAndSettle();
          }
          final page = tester.element(find.byWidget(screen));
          final chips = tester
              .elementList(find.byType(AccountStatusChip))
              .toList();
          TextEditingController? draft;
          if (editor) {
            draft = tester
                .widget<TextField>(find.byType(TextField).first)
                .controller!;
            draft.value = const TextEditingValue(
              text: 'Synthetic draft',
              selection: TextSelection.collapsed(offset: 4),
            );
            await tester.pumpAndSettle();
          }
          final observations = <Map<String, Object?>>[];
          final other = initial == AppLocale.zh ? AppLocale.en : AppLocale.zh;
          for (final next in [initial, other, initial]) {
            await tester.runAsync(() => locale.setLocale(next));
            await tester.pumpAndSettle();
            expect(tester.element(find.byWidget(screen)), same(page));
            final retainedChips = tester
                .elementList(find.byType(AccountStatusChip))
                .toList();
            expect(retainedChips.length, chips.length);
            for (var i = 0; i < chips.length; i++) {
              expect(retainedChips[i], same(chips[i]));
            }
            if (draft != null) {
              expect(
                tester
                    .widget<TextField>(find.byType(TextField).first)
                    .controller,
                same(draft),
              );
              expect(draft.text, 'Synthetic draft');
              expect(draft.selection.baseOffset, 4);
            }
            final actual = <String>[];
            final expected = <String>[];
            for (final chip in tester.widgetList<AccountStatusChip>(
              find.byType(AccountStatusChip),
            )) {
              final descendant = find.descendant(
                of: find.byWidget(chip),
                matching: find.byType(Text),
              );
              actual.add(tester.widget<Text>(descendant).data!);
              expected.add(_label(chip.status));
            }
            observations.add({
              'locale': next.name,
              'actual': actual,
              'expected': expected,
            });
            await _capture(
              tester,
              capture,
              '$name-${observations.length}-${next.name}',
            );
          }
          final output = Platform.environment['DUOYI_ROUTE_BACKDROP_EVIDENCE'];
          if (output != null) {
            final file = File('$output/$name.json');
            file.parent.createSync(recursive: true);
            file.writeAsStringSync(
              jsonEncode({
                'name': name,
                'observations': observations,
                'profileDraftRetained': draft != null,
                'productionRoot': host != _Host.brandedStandalone,
              }),
            );
          }
          for (final observation in observations) {
            expect(
              observation['actual'],
              observation['expected'],
              reason:
                  '$name ${observation['locale']}: retained labels follow active language',
            );
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}

// Keep the real root/Navigator/locale machinery while isolating MainShell,
// startup hydration and real requests. This does not simulate an account logout.
class _FixtureAuth extends AuthProvider {
  _FixtureAuth(ApiClient client, bool account)
    : super(
        client: client,
        initialState: account
            ? const AuthState(
                userId: 'synthetic',
                username: 'Synthetic',
                token: 'synthetic-token',
              )
            : const AuthState(),
      );
  @override
  bool get isLocalAccountDataBlocked => true;
}

class _Updater extends AppUpdateService {
  _Updater() : super(repo: 'synthetic/unused', currentVersion: '0.0.0');
  @override
  Future<void> checkServerPolicyNow() async {}
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final output = Platform.environment['DUOYI_ROUTE_BACKDROP_SCREENSHOTS'];
  if (output == null) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      final file = File('$output/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
