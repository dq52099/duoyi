import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/account_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/user_provider.dart';
import 'package:duoyi/screens/profile_screen.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:duoyi/widgets/brand_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/widget_polish_screenshot_font.dart';
import '../support/rendered_control_contrast.dart';
import '../support/rendered_information_chip_contrast.dart';

void main() {
  testWidgets('pending mirror retries latest confirmed avatar and email', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.zh);
    final user = _RejectingMirrorUser();
    final theme = ThemeProvider();
    var patches = 0;
    final auth = AuthProvider(
      initialState: const AuthState(
        userId: 'latest-profile',
        username: 'latest-account',
        token: 'synthetic-latest-token',
      ),
      client: ApiClient(
        baseUrl: 'https://duoyi.test',
        token: 'synthetic-latest-token',
        httpClient: MockClient((request) async {
          patches++;
          return http.Response(
            jsonEncode({
              'user_id': 'latest-profile',
              'username': 'latest-account',
              'display_name': 'Confirmed $patches',
              'email': 'confirmed-$patches@example.test',
              'avatar': 'Avatar $patches',
              'bio': 'Biography $patches',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      auth.dispose();
      user.dispose();
      theme.dispose();
      I18n.setLocale(AppLocale.zh);
      SharedPreferences.setMockInitialValues({});
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<UserProvider>.value(value: user),
          ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ],
        child: MaterialApp(
          theme: theme.brand.theme,
          home: const BrandRouteSurface(
            remountOnLocaleChange: false,
            child: ProfileScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, I18n.tr('action.save'));
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(patches, 1);
    expect(find.text(AccountUiCopy.profileSavedLocalSyncFailed), findsWidgets);

    // Hold a local retry while a later accepted server change arrives.
    user.reject = false;
    final release = user.hold = Completer<void>();
    await tester.tap(save);
    await tester.pump();
    expect(user.mirrorAttempts, 2);
    var updated = false;
    final update = auth
        .updateProfile(displayName: 'Later server change')
        .whenComplete(() => updated = true);
    for (var frame = 0; frame < 100 && !updated; frame++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(updated, isTrue);
    await update;
    user.hold = null;
    release.complete();
    await tester.pumpAndSettle();
    expect(patches, 2);
    expect(auth.state.avatar, 'Avatar 2');
    expect(auth.state.email, 'confirmed-2@example.test');
    expect(user.profile.avatarUrl, 'Avatar 1');
    expect(find.text(AccountUiCopy.feedbackLocalSynced), findsNothing);
    expect(find.text(AccountUiCopy.profileSavedLocalSyncFailed), findsWidgets);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(patches, 2, reason: 'The pending mirror retry sends no new PATCH.');
    expect(user.profile.displayName, 'Confirmed 2');
    expect(user.profile.email, 'confirmed-2@example.test');
    expect(user.profile.avatarUrl, 'Avatar 2');
    expect(user.profile.bio, 'Biography 2');
    for (final field in [
      (label: 'profile.nickname', value: 'Confirmed 2'),
      (label: 'profile.bio', value: 'Biography 2'),
    ]) {
      final finder = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == I18n.tr(field.label),
      );
      expect(
        tester.widget<TextField>(finder).controller!.text,
        field.value,
        reason: 'A clean form must not retain stale values for its next Save.',
      );
    }
    expect(tester.takeException(), isNull);
  });

  for (final locale in AppLocale.values) {
    for (final layout in const [
      (name: 'narrow', size: Size(320, 844), scale: 1.3),
      (name: 'landscape', size: Size(568, 320), scale: 1.6),
    ]) {
      testWidgets('profile mirror feedback ${locale.name} ${layout.name}', (
        tester,
      ) async {
        SharedPreferences.setMockInitialValues({});
        I18n.setLocale(locale);
        await tester.runAsync(_loadFonts);
        tester.view.physicalSize = layout.size;
        tester.view.devicePixelRatio = 1;
        final user = _RejectingMirrorUser();
        final theme = ThemeProvider();
        var patches = 0;
        final auth = AuthProvider(
          initialState: const AuthState(
            userId: 'layout-profile',
            username: 'layout-account',
            displayName: 'Initial profile',
            token: 'synthetic-layout-token',
          ),
          client: ApiClient(
            baseUrl: 'https://duoyi.test',
            token: 'synthetic-layout-token',
            httpClient: MockClient((request) async {
              expect(request.method, 'PATCH');
              expect(request.url.path, '/api/me/profile');
              patches++;
              return http.Response(
                jsonEncode({
                  'user_id': 'layout-profile',
                  'username': 'layout-account',
                  'display_name': 'Saved profile',
                  'bio': 'Saved biography',
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            }),
          ),
        );
        // Model main.dart's best-effort mirror before the screen's final mirror.
        // Both attempts fail, so a one-shot failure cannot self-heal invisibly.
        auth.onAccountProfileChanged = (state) => user.updateProfile(
          username: state.username ?? '',
          displayName: state.displayName,
          bio: state.bio,
        );
        final boundary = GlobalKey();
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          auth.dispose();
          user.dispose();
          theme.dispose();
          tester.view.reset();
          I18n.setLocale(AppLocale.zh);
          SharedPreferences.setMockInitialValues({});
        });
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<AuthProvider>.value(value: auth),
              ChangeNotifierProvider<UserProvider>.value(value: user),
              ChangeNotifierProvider<ThemeProvider>.value(value: theme),
            ],
            child: MaterialApp(
              theme: theme.brand.theme.copyWith(platform: TargetPlatform.iOS),
              builder: (context, child) => RepaintBoundary(
                key: boundary,
                child: MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(layout.scale)),
                  child: child!,
                ),
              ),
              home: const BrandRouteSurface(
                remountOnLocaleChange: false,
                child: ProfileScreen(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(FilledButton, I18n.tr('action.save')),
        );
        await tester.pumpAndSettle();
        expect(patches, 1);
        expect(user.mirrorAttempts, 2);
        expect(auth.state.displayName, 'Saved profile');
        expect(user.profile.displayName, isNot('Saved profile'));
        expect(
          find.text(AccountUiCopy.profileSavedLocalSyncFailed),
          findsWidgets,
        );
        expect(find.text(I18n.tr('profile.save_failed')), findsNothing);
        ScaffoldMessenger.of(
          tester.element(find.byType(ProfileScreen)),
        ).removeCurrentSnackBar();
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(TextButton, AccountUiCopy.actionRetry),
          findsNothing,
          reason: 'Profile recovery must not be presented as an email action.',
        );
        final banner = find.widgetWithText(
          AppInfoBanner,
          AccountUiCopy.localProfileSyncPendingTitle,
        );
        await tester.scrollUntilVisible(
          banner,
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(OutlinedButton, AccountUiCopy.actionRetry),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await _capture(tester, boundary, '${locale.name}-${layout.name}');

        // A subsequent Save without new edits must recover only the local write.
        user.reject = false;
        await tester.tap(
          find.widgetWithText(FilledButton, I18n.tr('action.save')),
        );
        await tester.pumpAndSettle();
        expect(patches, 1);
        expect(user.mirrorAttempts, 3);
        expect(user.profile.displayName, 'Saved profile');
        expect(user.profile.bio, 'Saved biography');
        expect(
          find.text(AccountUiCopy.profileSavedLocalSyncFailed),
          findsNothing,
        );
        expect(find.text(AccountUiCopy.feedbackLocalSynced), findsWidgets);
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final layout in const [
        (name: 'portrait', size: Size(320, 844)),
        (name: 'landscape', size: Size(568, 320)),
      ]) {
        testWidgets(
          'profile snackbar retry is readable $brand ${locale.name} ${layout.name}',
          (tester) => withControlEvidenceShadows(() async {
            SharedPreferences.setMockInitialValues({'active_brand': brand});
            I18n.setLocale(locale);
            await tester.runAsync(_loadFonts);
            tester.view.physicalSize = layout.size;
            tester.view.devicePixelRatio = 1;
            final user = _RejectingMirrorUser();
            final theme = ThemeProvider();
            await theme.loadFromStorage();
            var patches = 0;
            final auth = AuthProvider(
              initialState: const AuthState(
                userId: 'snackbar-profile',
                username: 'snackbar-account',
                token: 'synthetic-snackbar-token',
              ),
              client: ApiClient(
                baseUrl: 'https://duoyi.test',
                token: 'synthetic-snackbar-token',
                httpClient: MockClient((request) async {
                  expect(request.method, 'PATCH');
                  expect(request.url.path, '/api/me/profile');
                  patches++;
                  return http.Response(
                    jsonEncode({
                      'user_id': 'snackbar-profile',
                      'username': 'snackbar-account',
                      'display_name': 'Saved profile',
                      'bio': 'Saved biography',
                    }),
                    200,
                    headers: {'content-type': 'application/json'},
                  );
                }),
              ),
            );
            auth.onAccountProfileChanged = (state) => user.updateProfile(
              username: state.username ?? '',
              displayName: state.displayName,
              bio: state.bio,
            );
            final boundary = GlobalKey();
            addTearDown(() async {
              await tester.pumpWidget(const SizedBox.shrink());
              auth.dispose();
              user.dispose();
              theme.dispose();
              tester.view.reset();
              I18n.setLocale(AppLocale.zh);
              SharedPreferences.setMockInitialValues({});
            });
            await tester.pumpWidget(
              MultiProvider(
                providers: [
                  ChangeNotifierProvider<AuthProvider>.value(value: auth),
                  ChangeNotifierProvider<UserProvider>.value(value: user),
                  ChangeNotifierProvider<ThemeProvider>.value(value: theme),
                ],
                child: MaterialApp(
                  theme: theme.brand.theme.copyWith(
                    platform: TargetPlatform.iOS,
                  ),
                  builder: (context, child) => RepaintBoundary(
                    key: boundary,
                    child: MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(textScaler: const TextScaler.linear(1.6)),
                      child: child!,
                    ),
                  ),
                  home: const BrandRouteSurface(
                    remountOnLocaleChange: false,
                    child: ProfileScreen(),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            await expectInformationChipContrast(tester, boundary, [
              AccountUiCopy.statusLoggedIn,
              '${I18n.tr('profile.coins')} ${auth.state.coinBalance}',
              '${I18n.tr('profile.account_id')} ${auth.state.username}',
            ]);
            await tester.tap(
              find.widgetWithText(FilledButton, I18n.tr('action.save')),
            );
            await tester.pumpAndSettle();
            expect(patches, 1);
            expect(user.mirrorAttempts, 2);
            final retry = find.descendant(
              of: find.byType(SnackBar),
              matching: find.widgetWithText(
                TextButton,
                AccountUiCopy.actionRetry,
              ),
            );
            expect(retry, findsOneWidget);
            expectReadableControl(tester, retry);
            await _captureRetry(
              tester,
              boundary,
              '$brand-${locale.name}-${layout.name}',
            );
            user.reject = false;
            await tester.tap(retry);
            await tester.pumpAndSettle();
            expect(
              patches,
              1,
              reason: 'Local recovery must not send another PATCH.',
            );
            expect(user.mirrorAttempts, 3);
            expect(user.profile.displayName, 'Saved profile');
            expect(user.profile.bio, 'Saved biography');
            expect(find.text(AccountUiCopy.feedbackLocalSynced), findsWidgets);
            expect(tester.takeException(), isNull);
          }),
        );
      }
    }
  }
}

class _RejectingMirrorUser extends UserProvider {
  bool reject = true;
  int mirrorAttempts = 0;
  Completer<void>? hold;

  @override
  Future<void> updateProfile({
    required String username,
    String? avatarInitials,
    String? displayName,
    String? email,
    bool? emailVerified,
    String? avatarUrl,
    String? bio,
  }) async {
    mirrorAttempts++;
    final pending = hold;
    if (pending != null) await pending.future;
    if (reject) throw StateError('Synthetic local profile write failure');
    await super.updateProfile(
      username: username,
      avatarInitials: avatarInitials,
      displayName: displayName,
      email: email,
      emailVerified: emailVerified,
      avatarUrl: avatarUrl,
      bio: bio,
    );
  }
}

Future<void> _capture(
  WidgetTester tester,
  GlobalKey boundary,
  String name,
) async {
  if (Platform.environment['DUOYI_CAPTURE_SETTINGS_SCREENSHOTS'] != '1') return;
  await tester.pump();
  await tester.runAsync(() async {
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await render.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File(
      'evidence/screenshots/profile-mirror-recovery-20261015/$name.png',
    );
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Future<void> _loadFonts() async {
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
  for (final family in [
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

Future<void> _captureRetry(
  WidgetTester tester,
  GlobalKey boundary,
  String name,
) async {
  if (Platform.environment['DUOYI_CAPTURE_PROFILE_RETRY'] != '1') return;
  await tester.runAsync(() async {
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await render.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final screenshotDirectory =
          Platform.environment['DUOYI_PROFILE_RETRY_SCREENSHOT_DIR'] ??
          'evidence/screenshots/widget-native-runtime-20261019';
      final file = File('$screenshotDirectory/profile-retry-$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
