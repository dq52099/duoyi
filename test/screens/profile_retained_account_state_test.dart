import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// ignore: depend_on_referenced_packages
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/account_ui_copy.dart';
import 'package:duoyi/core/account_preference_writes.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/user_provider.dart';
import 'package:duoyi/screens/profile_screen.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.zh);
  });
  tearDown(() => I18n.setLocale(AppLocale.zh));

  for (final sameUser in [false, true]) {
    testWidgets(
      'retained profile draft cannot submit into a replacement session sameUser=$sameUser',
      (tester) async {
        final auth = _RecordingAuth();
        final user = UserProvider();
        await _pump(tester, auth, user);
        await tester.enterText(
          _field('profile.nickname'),
          'A unsaved nickname',
        );
        await tester.enterText(_field('profile.bio'), 'A unsaved biography');
        final draft = tester
            .widget<TextField>(_field('profile.nickname'))
            .controller!;
        await _replaceSession(tester, auth, sameUser: sameUser);
        // The origin draft can remain for recovery; it may not authorize B.
        expect(draft.text, 'A unsaved nickname');
        await tester.tap(
          find.widgetWithText(FilledButton, I18n.tr('action.save')),
        );
        await tester.pumpAndSettle();
        expect(auth.acceptedProfileWrites, 0);
        expect(auth.state.userId, sameUser ? 'profile-A' : 'profile-B');
        expect(user.profile.displayName, 'local prior');
        expect(find.text(I18n.tr('profile.updated')), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final error in [false, true]) {
    testWidgets(
      'held profile save result $error cannot mirror or announce after replacement',
      (tester) async {
        final auth = _RecordingAuth()..holdProfile = true;
        final user = UserProvider();
        await _pump(tester, auth, user);
        await tester.enterText(_field('profile.nickname'), 'held nickname');
        await tester.tap(
          find.widgetWithText(FilledButton, I18n.tr('action.save')),
        );
        await tester.pump();
        expect(auth.acceptedProfileWrites, 1);
        await _replaceSession(tester, auth);
        if (error) {
          auth.profileRelease.completeError(
            StateError('synthetic departed save'),
          );
        } else {
          auth.profileRelease.complete();
        }
        await tester.pumpAndSettle();
        expect(user.profile.displayName, 'local prior');
        expect(find.text(I18n.tr('profile.updated')), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'held profile save error is discarded while its route is covered',
    (tester) async {
      final auth = _RecordingAuth()..holdProfile = true;
      final user = UserProvider();
      await _pump(tester, auth, user);
      await tester.enterText(_field('profile.nickname'), 'covered nickname');
      await tester.tap(
        find.widgetWithText(FilledButton, I18n.tr('action.save')),
      );
      await tester.pump();
      expect(auth.acceptedProfileWrites, 1);

      await _coverCurrentRoute(tester);
      auth.profileRelease.completeError(
        StateError('synthetic covered profile failure'),
      );
      await tester.pumpAndSettle();
      await _returnFromCoveredRoute(tester);

      expect(find.text(I18n.tr('profile.save_failed')), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('profile fields are disabled during a held save', (tester) async {
    final auth = _RecordingAuth()..holdProfile = true;
    final user = UserProvider();
    await _pump(tester, auth, user);
    await tester.enterText(_field('profile.nickname'), 'saving nickname');
    await tester.enterText(_field('profile.bio'), 'saving biography');
    await tester.tap(find.widgetWithText(FilledButton, I18n.tr('action.save')));
    await tester.pump();

    expect(
      tester.widget<TextField>(_field('profile.nickname')).enabled,
      isFalse,
    );
    expect(tester.widget<TextField>(_field('profile.bio')).enabled, isFalse);
    auth.profileRelease.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'retained password dialog cannot change replacement session password',
    (tester) async {
      final auth = _RecordingAuth();
      final user = UserProvider();
      await _pump(tester, auth, user);
      final action = find.widgetWithText(
        TextButton,
        I18n.tr('profile.change_password'),
      );
      await tester.scrollUntilVisible(
        action,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(action);
      await tester.pumpAndSettle();
      await tester.enterText(
        _field('profile.current_password'),
        'synthetic-current',
      );
      await tester.enterText(_field('auth.new_password'), 'synthetic-next');
      await tester.enterText(
        _field('profile.confirm_new_password'),
        'synthetic-next',
      );
      await _replaceSession(tester, auth);
      await tester.tap(
        find.descendant(
          of: find.byType(AppDialog),
          matching: find.widgetWithText(FilledButton, I18n.tr('action.save')),
        ),
      );
      await tester.pumpAndSettle();
      expect(auth.acceptedPasswordWrites, 0);
      expect(auth.state.isLoggedIn, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final action in ['send', 'bind']) {
    testWidgets(
      'retained email dialog $action cannot operate replacement session',
      (tester) async {
        final auth = _RecordingAuth();
        final user = UserProvider();
        await _pump(tester, auth, user);
        final entrance = find.widgetWithText(
          TextButton,
          I18n.tr('profile.email.binding'),
        );
        await tester.scrollUntilVisible(
          entrance,
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(entrance);
        await tester.pumpAndSettle();
        await tester.enterText(_field('auth.email'), 'draft-A@example.test');
        await tester.enterText(_field('auth.email_code'), '123456');
        await _replaceSession(tester, auth);
        final button = action == 'send'
            ? find.widgetWithText(FilledButton, I18n.tr('auth.send'))
            : find.widgetWithText(
                FilledButton,
                I18n.tr('profile.email.binding'),
              );
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(auth.acceptedEmailCodes, 0);
        expect(auth.acceptedEmailBindings, 0);
        expect(user.profile.displayName, 'local prior');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final error in [false, true]) {
    testWidgets(
      'held email code result $error does not start cooldown after session replacement',
      (tester) async {
        final auth = _RecordingAuth()..holdEmailCode = true;
        final user = UserProvider();
        await _pump(tester, auth, user);
        final entrance = find.widgetWithText(
          TextButton,
          I18n.tr('profile.email.binding'),
        );
        await tester.scrollUntilVisible(
          entrance,
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(entrance);
        await tester.pumpAndSettle();
        await tester.enterText(_field('auth.email'), 'draft-A@example.test');
        await tester.pump();
        await tester.tap(
          find.widgetWithText(FilledButton, I18n.tr('auth.send')),
        );
        await tester.pump();
        expect(auth.acceptedEmailCodes, 1);
        await _replaceSession(tester, auth);
        if (error) {
          auth.emailCodeRelease.completeError(
            StateError('synthetic departed email'),
          );
        } else {
          auth.emailCodeRelease.complete();
        }
        await tester.pumpAndSettle();
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Text && RegExp(r'^\d+s$').hasMatch(widget.data ?? ''),
          ),
          findsNothing,
        );
        expect(find.byType(SnackBar), findsNothing);
        expect(auth.acceptedEmailBindings, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final action in ['send', 'bind']) {
    testWidgets(
      'held email $action error is discarded while its dialog is covered',
      (tester) async {
        final auth = _RecordingAuth()
          ..holdEmailCode = action == 'send'
          ..holdEmailBind = action == 'bind';
        final user = UserProvider();
        await _pump(tester, auth, user);
        await _openEmailBindingDialog(tester);
        final button = action == 'send'
            ? find.widgetWithText(FilledButton, I18n.tr('auth.send'))
            : find.widgetWithText(
                FilledButton,
                I18n.tr('profile.email.binding'),
              );
        await tester.tap(button);
        await tester.pump();
        expect(
          action == 'send'
              ? auth.acceptedEmailCodes
              : auth.acceptedEmailBindings,
          1,
        );

        await _coverCurrentRoute(tester, host: find.byType(AppDialog));
        if (action == 'send') {
          auth.emailCodeRelease.completeError(
            StateError('synthetic covered email send failure'),
          );
        } else {
          auth.emailBindRelease.completeError(
            StateError('synthetic covered email bind failure'),
          );
        }
        await tester.pumpAndSettle();
        await _returnFromCoveredRoute(tester);

        expect(
          find.descendant(
            of: find.byType(AppDialog),
            matching: find.byType(AppInfoBanner),
          ),
          findsNothing,
        );
        expect(find.byType(SnackBar), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets(
      'retained email $action callback cannot issue a request while covered',
      (tester) async {
        final auth = _RecordingAuth();
        final user = UserProvider();
        await _pump(tester, auth, user);
        await _openEmailBindingDialog(tester);
        final button = action == 'send'
            ? find.widgetWithText(FilledButton, I18n.tr('auth.send'))
            : find.widgetWithText(
                FilledButton,
                I18n.tr('profile.email.binding'),
              );
        final retainedCallback = tester.widget<FilledButton>(button).onPressed!;

        await _coverCurrentRoute(tester, host: find.byType(AppDialog));
        retainedCallback();
        await tester.pump();
        expect(auth.acceptedEmailCodes, 0);
        expect(auth.acceptedEmailBindings, 0);
        await _returnFromCoveredRoute(tester);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('real password success closes dialog after intentional logout', (
    tester,
  ) async {
    final release = Completer<http.Response>();
    var calls = 0;
    final auth = AuthProvider(
      initialState: const AuthState(
        userId: 'password-A',
        username: 'A',
        token: 'synthetic-password-A',
      ),
      client: ApiClient(
        baseUrl: 'https://duoyi.test',
        token: 'synthetic-password-A',
        httpClient: MockClient((request) async {
          if (request.method == 'POST' &&
              request.url.path == '/api/me/password') {
            calls++;
            return release.future;
          }
          return http.Response('not found', 404);
        }),
      ),
    );
    final user = UserProvider();
    await _pump(tester, auth, user);
    final entrance = find.widgetWithText(
      TextButton,
      I18n.tr('profile.change_password'),
    );
    await tester.scrollUntilVisible(
      entrance,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(entrance);
    await tester.pumpAndSettle();
    await tester.enterText(
      _field('profile.current_password'),
      'synthetic-current',
    );
    await tester.enterText(_field('auth.new_password'), 'synthetic-next');
    await tester.enterText(
      _field('profile.confirm_new_password'),
      'synthetic-next',
    );
    await tester.tap(
      find.descendant(
        of: find.byType(AppDialog),
        matching: find.widgetWithText(FilledButton, I18n.tr('action.save')),
      ),
    );
    await tester.pump();
    expect(calls, 1);
    I18n.setLocale(AppLocale.en);
    await tester.pump();
    release.complete(
      http.Response('{}', 200, headers: {'content-type': 'application/json'}),
    );
    for (var frame = 0; frame < 100 && auth.state.isLoggedIn; frame++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
    expect(auth.state.isLoggedIn, isFalse);
    expect(_field('profile.current_password'), findsNothing);
    expect(find.byType(SnackBar), findsOneWidget);
    final text = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(SnackBar),
            matching: find.byType(Text),
          ),
        )
        .map((v) => v.data ?? '')
        .join(' ');
    expect(text.toLowerCase(), contains('password'));
    expect(RegExp(r'[\u3400-\u9fff]').hasMatch(text), isFalse);
    I18n.setLocale(AppLocale.zh);
    await tester.pump();
    expect(
      find.text(AccountUiCopy.feedbackPasswordChangedRelogin),
      findsOneWidget,
    );
    I18n.setLocale(AppLocale.en);
    await tester.pump();
    expect(
      find.text(AccountUiCopy.feedbackPasswordChangedRelogin),
      findsOneWidget,
    );
    expect(calls, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final recovery in ['success', 'replacement', 'coveredRoute', 'locale']) {
    testWidgets('bound server email local mirror recovery: $recovery', (
      tester,
    ) async {
      final store = _ProfileRejectStore();
      SharedPreferencesStorePlatform.instance = store;
      var bindings = 0;
      final auth = AuthProvider(
        initialState: const AuthState(
          userId: 'email-A',
          username: 'A',
          email: 'old@example.test',
          token: 'synthetic-email-A',
        ),
        client: ApiClient(
          baseUrl: 'https://duoyi.test',
          token: 'synthetic-email-A',
          httpClient: MockClient((request) async {
            if (request.method == 'PATCH' &&
                request.url.path == '/api/me/email') {
              bindings++;
              return http.Response(
                jsonEncode({
                  'user_id': 'email-A',
                  'username': 'A',
                  'email': 'next@example.test',
                  'email_verified': true,
                  'display_name': 'A display',
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            return http.Response('not found', 404);
          }),
        ),
      );
      final user = UserProvider();
      await _pump(tester, auth, user);
      final priorEmail = user.profile.email;
      await tester.enterText(_field('profile.nickname'), 'A unsaved draft');
      await tester.pump();
      final entrance = find.widgetWithText(
        TextButton,
        I18n.tr('profile.email.binding'),
      );
      await tester.scrollUntilVisible(
        entrance,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(entrance);
      await tester.pumpAndSettle();
      await tester.enterText(_field('auth.email'), 'next@example.test');
      await tester.enterText(_field('auth.email_code'), '123456');
      store.rejectNext = true;
      await tester.tap(
        find.widgetWithText(FilledButton, I18n.tr('profile.email.binding')),
      );
      await tester.pumpAndSettle();
      expect(bindings, 1);
      expect(auth.state.email, 'next@example.test');
      expect(auth.state.emailVerified, isTrue);
      expect(user.profile.email, priorEmail);
      expect(
        tester.widget<TextField>(_field('profile.nickname')).controller!.text,
        'A unsaved draft',
      );
      expect(find.text(AccountUiCopy.emailBoundLocalSyncFailed), findsWidgets);
      expect(find.text(I18n.tr('profile.updated')), findsNothing);
      expect(tester.takeException(), isNull);
      if (recovery == 'locale') {
        I18n.setLocale(AppLocale.en);
        await tester.pumpAndSettle();
        final bar = find.byType(SnackBar);
        expect(
          find.descendant(
            of: bar,
            matching: find.text(AccountUiCopy.emailBoundLocalSyncFailed),
          ),
          findsOneWidget,
        );
        final labels = tester
            .widgetList<Text>(
              find.descendant(of: bar, matching: find.byType(Text)),
            )
            .map((text) => text.data ?? '');
        expect(
          labels.where((label) => RegExp(r'[\u3400-\u9fff]').hasMatch(label)),
          isEmpty,
        );
        I18n.setLocale(AppLocale.zh);
        await tester.pumpAndSettle();
      }
      ScaffoldMessenger.of(
        tester.element(find.byType(ProfileScreen)),
      ).removeCurrentSnackBar();
      await tester.pumpAndSettle();
      final retry = find
          .ancestor(
            of: find.textContaining('重试'),
            matching: find.byWidgetPredicate(
              (widget) => widget is ButtonStyleButton,
            ),
          )
          .first;
      await tester.scrollUntilVisible(
        retry,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      final callback = tester.widget<ButtonStyleButton>(retry).onPressed!;
      if (recovery == 'replacement') {
        await _replaceSession(tester, auth);
      } else if (recovery == 'coveredRoute') {
        Navigator.of(tester.element(find.byType(ProfileScreen))).push<void>(
          MaterialPageRoute(
            builder: (_) =>
                const Scaffold(body: Text('Current foreground route')),
          ),
        );
        await tester.pumpAndSettle();
      }
      if (recovery == 'replacement' || recovery == 'coveredRoute') {
        final writes = store.profileWrites;
        callback();
        await tester.pumpAndSettle();
        expect(
          store.profileWrites,
          writes,
          reason:
              'A retained recovery callback must not write off-route or across accounts.',
        );
        expect(bindings, 1);
        expect(user.profile.email, priorEmail);
        expect(find.byType(SnackBar), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        return;
      }
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(
        bindings,
        1,
        reason:
            'Retry the local mirror without sending another server binding.',
      );
      expect(user.profile.email, 'next@example.test');
      expect(user.profile.emailVerified, isTrue);
      expect(
        tester.widget<TextField>(_field('profile.nickname')).controller!.text,
        'A unsaved draft',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'profile server save retries only the local mirror and preserves later drafts',
    (tester) async {
      final store = _ProfileRejectStore();
      SharedPreferencesStorePlatform.instance = store;
      var profileRequests = 0;
      final auth = AuthProvider(
        initialState: const AuthState(
          userId: 'profile-A',
          username: 'account-A',
          displayName: 'A display',
          bio: 'A bio',
          token: 'synthetic-profile-A',
        ),
        client: ApiClient(
          baseUrl: 'https://duoyi.test',
          token: 'synthetic-profile-A',
          httpClient: MockClient((request) async {
            if (request.method == 'PATCH' &&
                request.url.path == '/api/me/profile') {
              profileRequests++;
              return http.Response(
                jsonEncode({
                  'user_id': 'profile-A',
                  'username': 'account-A',
                  'display_name': 'Server confirmed name',
                  'bio': 'Server confirmed biography',
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            return http.Response('not found', 404);
          }),
        ),
      );
      final user = UserProvider();
      // _pump deliberately omits main.dart's automatic profile callback so this
      // covers the screen's final local mirror after AuthProvider confirmation.
      await _pump(tester, auth, user);
      await tester.enterText(_field('profile.nickname'), 'Submitted name');
      await tester.enterText(_field('profile.bio'), 'Submitted biography');

      store.rejectNext = true;
      await tester.tap(
        find.widgetWithText(FilledButton, I18n.tr('action.save')),
      );
      await tester.pumpAndSettle();
      expect(profileRequests, 1);
      expect(auth.state.displayName, 'Server confirmed name');
      expect(auth.state.bio, 'Server confirmed biography');
      expect(user.profile.displayName, 'local prior');
      expect(
        find.text(AccountUiCopy.localProfileSyncPendingTitle),
        findsWidgets,
      );
      expect(
        find.text(AccountUiCopy.profileSavedLocalSyncFailed),
        findsWidgets,
      );

      final writesBeforeSecondSave = store.profileWrites;
      store.rejectNext = true;
      await tester.tap(
        find.widgetWithText(FilledButton, I18n.tr('action.save')),
      );
      await tester.pumpAndSettle();
      expect(profileRequests, 1);
      expect(store.profileWrites, greaterThan(writesBeforeSecondSave));
      expect(
        find.text(AccountUiCopy.profileSavedLocalSyncFailed),
        findsWidgets,
        reason: 'A failed local retry must keep the mirror pending.',
      );

      await tester.enterText(
        _field('profile.nickname'),
        'Later unsaved nickname',
      );
      await tester.enterText(_field('profile.bio'), 'Later unsaved biography');
      I18n.setLocale(AppLocale.en);
      await tester.pumpAndSettle();
      expect(
        find.text(AccountUiCopy.localProfileSyncPendingTitle),
        findsWidgets,
      );
      expect(
        find.text(AccountUiCopy.profileSavedLocalSyncFailed),
        findsWidgets,
      );
      expect(
        find.text(I18n.tr('profile.save_failed')),
        findsNothing,
        reason: 'The server save succeeded, so this needs distinct copy.',
      );
      I18n.setLocale(AppLocale.zh);
      await tester.pumpAndSettle();
      ScaffoldMessenger.of(
        tester.element(find.byType(ProfileScreen)),
      ).removeCurrentSnackBar();
      await tester.pumpAndSettle();

      final retry = find
          .ancestor(
            of: find.text(AccountUiCopy.actionRetry),
            matching: find.byWidgetPredicate(
              (widget) => widget is ButtonStyleButton,
            ),
          )
          .first;
      await tester.scrollUntilVisible(
        retry,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(retry);
      await tester.pumpAndSettle();

      expect(profileRequests, 1);
      expect(user.profile.displayName, auth.state.displayName);
      expect(user.profile.bio, auth.state.bio);
      expect(
        tester.widget<TextField>(_field('profile.nickname')).controller!.text,
        'Later unsaved nickname',
      );
      expect(
        tester.widget<TextField>(_field('profile.bio')).controller!.text,
        'Later unsaved biography',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final reject in [false, true]) {
    testWidgets('local avatar storage acknowledgement reject=$reject', (
      tester,
    ) async {
      final store = _ProfileRejectStore();
      SharedPreferencesStorePlatform.instance = store;
      final auth = AuthProvider();
      final user = UserProvider();
      await _pump(tester, auth, user);
      final directory = await tester.runAsync(
        () => Directory.systemTemp.createTemp('duoyi-profile-avatar-'),
      );
      final originalPaths = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _AvatarDocuments(directory!.path);
      final originalSelector = FileSelectorPlatform.instance;
      FileSelectorPlatform.instance = _SyntheticAvatarSelector();
      addTearDown(() async {
        FileSelectorPlatform.instance = originalSelector;
        PathProviderPlatform.instance = originalPaths;
        await directory.delete(recursive: true);
      });
      store.rejectNext = reject;
      final beforeWrites = store.profileWrites;
      final oldAvatar = user.profile.avatarUrl;
      await tester.tap(
        find.byKey(const ValueKey('profile_avatar_edit_button')),
      );
      // Real file IO and fake-async preference callbacks must both advance.
      // Blocking in runAsync on the fake-zone write queue deadlocks the fixture.
      for (var attempt = 0; attempt < 100; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
        if (store.profileWrites > beforeWrites &&
            find.byType(CircularProgressIndicator).evaluate().isEmpty) {
          break;
        }
      }
      expect(store.profileWrites, greaterThan(beforeWrites));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await AccountPreferenceWrites.drain();
      await tester.pumpAndSettle();
      expect(store.profileWrites, greaterThan(beforeWrites));
      final prefs = await SharedPreferences.getInstance();
      final stored =
          jsonDecode(prefs.getString('user_profile')!) as Map<String, dynamic>;
      if (reject) {
        expect(user.profile.avatarUrl, oldAvatar);
        expect(stored['avatarUrl'], oldAvatar);
        expect(find.text(I18n.tr('profile.avatar.saved')), findsNothing);
        expect(find.text(I18n.tr('profile.save_failed')), findsWidgets);
      } else {
        expect(
          user.profile.avatarUrl,
          startsWith('${directory.path}/profile_avatars/'),
        );
        expect(stored['avatarUrl'], user.profile.avatarUrl);
        expect(
          await tester.runAsync(() => File(user.profile.avatarUrl).exists()),
          isTrue,
        );
        expect(find.text(I18n.tr('profile.avatar.saved')), findsWidgets);
        await tester.pumpWidget(const SizedBox.shrink());
        final restored = UserProvider();
        addTearDown(restored.dispose);
        await restored.loadFromStorage();
        expect(restored.profile.avatarUrl, user.profile.avatarUrl);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

Finder _field(String key) => find.byWidgetPredicate(
  (widget) =>
      widget is TextField && widget.decoration?.labelText == I18n.tr(key),
);

Future<void> _openEmailBindingDialog(WidgetTester tester) async {
  final entrance = find.widgetWithText(
    TextButton,
    I18n.tr('profile.email.binding'),
  );
  await tester.scrollUntilVisible(
    entrance,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(entrance);
  await tester.pumpAndSettle();
  await tester.enterText(_field('auth.email'), 'draft-A@example.test');
  await tester.enterText(_field('auth.email_code'), '123456');
  await tester.pump();
}

Future<void> _coverCurrentRoute(WidgetTester tester, {Finder? host}) async {
  Navigator.of(tester.element(host ?? find.byType(ProfileScreen))).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('Covered foreground route')),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _returnFromCoveredRoute(WidgetTester tester) async {
  Navigator.of(tester.element(find.text('Covered foreground route'))).pop();
  await tester.pumpAndSettle();
}

Future<void> _pump(
  WidgetTester tester,
  AuthProvider auth,
  UserProvider user,
) async {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(auth.dispose);
  addTearDown(user.dispose);
  final theme = ThemeProvider();
  addTearDown(theme.dispose);
  await user.applyAccountSnapshot(
    username: 'local prior',
    displayName: 'local prior',
  );
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<UserProvider>.value(value: user),
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
      ],
      child: MaterialApp(theme: theme.brand.theme, home: const ProfileScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _replaceSession(
  WidgetTester tester,
  AuthProvider auth, {
  bool sameUser = false,
}) async {
  var finished = false;
  final pending = () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'auth_state',
      jsonEncode(
        AuthState(
          userId: sameUser ? 'profile-A' : 'profile-B',
          username: 'account-B',
          displayName: 'B display',
          email: 'B@example.test',
          token: 'synthetic-session-B',
        ).toJson(),
      ),
    );
    await auth.loadFromStorage(refreshServerConfig: false);
  }().whenComplete(() => finished = true);
  for (var frame = 0; frame < 100 && !finished; frame++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(finished, isTrue);
  await pending;
  // A deliberately held request still animates its progress indicator.
  await tester.pump(const Duration(milliseconds: 50));
  expect(auth.state.userId, sameUser ? 'profile-A' : 'profile-B');
}

// _pump does not wire main.dart's onAccountProfileChanged callback. This fake
// therefore isolates screen-owned local mirror writes from automatic sync.
class _RecordingAuth extends AuthProvider {
  _RecordingAuth()
    : super(
        initialState: const AuthState(
          userId: 'profile-A',
          username: 'account-A',
          displayName: 'A display',
          token: 'synthetic-session-A',
        ),
        client: ApiClient(
          baseUrl: 'https://duoyi.test',
          token: 'synthetic-session-A',
          httpClient: MockClient((_) async => http.Response('{}', 200)),
        ),
      );
  bool holdProfile = false;
  bool holdEmailCode = false;
  bool holdEmailBind = false;
  final profileRelease = Completer<void>();
  final emailCodeRelease = Completer<void>();
  final emailBindRelease = Completer<void>();
  int acceptedProfileWrites = 0;
  int acceptedPasswordWrites = 0;
  int acceptedEmailCodes = 0;
  int acceptedEmailBindings = 0;
  @override
  Future<void> updateProfile({
    String? displayName,
    String? bio,
    AuthSessionLease? sessionLease,
  }) async {
    if (sessionLease != null) requireCurrentSessionLease(sessionLease);
    acceptedProfileWrites++;
    if (holdProfile) await profileRelease.future;
    if (sessionLease != null) requireCurrentSessionLease(sessionLease);
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    AuthSessionLease? sessionLease,
  }) async {
    if (sessionLease != null) requireCurrentSessionLease(sessionLease);
    acceptedPasswordWrites++;
  }

  @override
  Future<Map<String, dynamic>> sendBindEmailCode({
    required String email,
    AuthSessionLease? sessionLease,
  }) async {
    if (sessionLease != null) requireCurrentSessionLease(sessionLease);
    acceptedEmailCodes++;
    if (holdEmailCode) await emailCodeRelease.future;
    if (sessionLease != null) requireCurrentSessionLease(sessionLease);
    return {};
  }

  @override
  Future<void> bindEmail({
    required String email,
    required String code,
    AuthSessionLease? sessionLease,
  }) async {
    if (sessionLease != null) requireCurrentSessionLease(sessionLease);
    acceptedEmailBindings++;
    if (holdEmailBind) await emailBindRelease.future;
    if (sessionLease != null) requireCurrentSessionLease(sessionLease);
  }
}

class _ProfileRejectStore extends InMemorySharedPreferencesStore {
  _ProfileRejectStore() : super.withData({});
  bool rejectNext = false;
  int profileWrites = 0;
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key == 'flutter.user_profile') profileWrites++;
    await super.setValue(type, key, value);
    if (key == 'flutter.user_profile' && rejectNext) {
      rejectNext = false;
      return false;
    }
    return true;
  }
}

class _AvatarDocuments extends PathProviderPlatform {
  _AvatarDocuments(this.directory);
  final String directory;
  @override
  Future<String?> getApplicationDocumentsPath() async => directory;
}

class _SyntheticAvatarSelector extends FileSelectorPlatform {
  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async => XFile.fromData(
    Uint8List.fromList(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jz1sAAAAASUVORK5CYII=',
      ),
    ),
    name: 'synthetic-avatar.png',
  );
}
