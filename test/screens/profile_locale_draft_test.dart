import 'dart:async';
import 'dart:convert';

import 'package:duoyi/core/app_version.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/achievement_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/notification_service.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/providers/user_provider.dart';
import 'package:duoyi/screens/mine_screen.dart';
import 'package:duoyi/screens/profile_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrapMine({
  required AuthProvider auth,
  required UserProvider userProvider,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => TodoProvider()),
      ChangeNotifierProvider(create: (_) => HabitProvider()),
      ChangeNotifierProvider(create: (_) => PomodoroProvider()),
      ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ChangeNotifierProvider<UserProvider>.value(value: userProvider),
      ChangeNotifierProvider(create: (_) => NotificationService()),
      ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ChangeNotifierProvider(create: (_) => AiService()),
      ChangeNotifierProvider(create: (_) => AchievementProvider()),
      ChangeNotifierProvider(
        create: (_) => AppUpdateService(
          repo: 'dq52099/duoyi',
          currentVersion: AppVersion.name,
        ),
      ),
    ],
    child: const MaterialApp(home: MineScreen()),
  );
}

ApiClient _testApiClient({
  required String token,
  required Future<http.Response> Function(http.Request request) handler,
}) {
  return ApiClient(
    baseUrl: 'https://duoyi.test',
    token: token,
    httpClient: MockClient(handler),
  );
}

Finder _mineListFinder() => find.byWidgetPredicate(
  (widget) =>
      widget is Scrollable && widget.restorationId == 'mine_screen_list',
);

Finder _profileField(String key) {
  if (key == 'profile.email.local_display' || key == 'profile_local_email_field') {
    return find.byKey(const ValueKey('profile_local_email_field'));
  }
  return find.widgetWithText(TextField, I18n.tr(key));
}

Finder _textFieldWithLabel(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Finder _cooldownLabel() => find.byWidgetPredicate(
  (widget) => widget is Text && RegExp(r'^\d+s$').hasMatch(widget.data ?? ''),
);

Finder _profileBanner({required String title, required String message}) =>
    find.byWidgetPredicate(
      (widget) =>
          widget is AppInfoBanner &&
          widget.title == title &&
          widget.message == message,
    );

Object _stateFor(WidgetTester tester, Finder finder) {
  final element = tester.element(finder);
  if (element is StatefulElement) return element.state;
  throw StateError('Stateful widget State was not found for $finder.');
}

Object _profileEditorState(WidgetTester tester, Finder descendant) {
  Element? element = tester.element(descendant);
  while (element != null) {
    if (element is StatefulElement &&
        element.state.runtimeType.toString().endsWith('ProfileEditorState')) {
      return element.state;
    }
    Element? parent;
    element.visitAncestorElements((ancestor) {
      parent = ancestor;
      return false;
    });
    element = parent;
  }
  throw StateError('Profile editor State was not found above the TextField.');
}

class _FieldSnapshot {
  const _FieldSnapshot({
    required this.controller,
    required this.focusNode,
    required this.text,
    required this.selection,
    required this.readOnly,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String text;
  final TextSelection selection;
  final bool readOnly;
}

Future<_FieldSnapshot> _enterDraft(
  WidgetTester tester, {
  required String key,
  required String text,
  required TextSelection selection,
}) async {
  final finder = _profileField(key);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.enterText(finder, text);
  final field = tester.widget<TextField>(finder);
  final controller = field.controller!;
  controller.selection = selection;
  await tester.pump();
  final editableFinder = find.descendant(
    of: finder,
    matching: find.byType(EditableText),
  );
  final editable = tester.widget<EditableText>(editableFinder);
  expect(editable.focusNode.hasFocus, isTrue);
  return _FieldSnapshot(
    controller: controller,
    focusNode: editable.focusNode,
    text: text,
    selection: selection,
    readOnly: field.readOnly,
  );
}

Future<_FieldSnapshot> _snapshotReadOnlyField(
  WidgetTester tester,
  String key,
) async {
  final finder = _profileField(key);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  final field = tester.widget<TextField>(finder);
  final controller = field.controller!;
  controller.selection = TextSelection.collapsed(
    offset: controller.text.length,
  );
  await tester.pump();
  final editable = tester.widget<EditableText>(
    find.descendant(of: finder, matching: find.byType(EditableText)),
  );
  expect(field.readOnly, isTrue);
  return _FieldSnapshot(
    controller: controller,
    focusNode: editable.focusNode,
    text: controller.text,
    selection: controller.selection,
    readOnly: field.readOnly,
  );
}

void _expectFieldPreserved(
  WidgetTester tester, {
  required String key,
  required _FieldSnapshot snapshot,
  required Object editorState,
  bool? expectHasFocus,
}) {
  final finder = _profileField(key);
  expect(finder, findsOneWidget);
  final field = tester.widget<TextField>(finder);
  expect(identical(field.controller, snapshot.controller), isTrue);
  expect(field.controller!.text, snapshot.text);
  expect(field.controller!.selection, snapshot.selection);
  expect(field.readOnly, snapshot.readOnly);
  final editable = tester.widget<EditableText>(
    find.descendant(of: finder, matching: find.byType(EditableText)),
  );
  expect(identical(editable.focusNode, snapshot.focusNode), isTrue);
  if (expectHasFocus != null) {
    expect(snapshot.focusNode.hasFocus, expectHasFocus);
    expect(editable.focusNode.hasFocus, expectHasFocus);
  }
  expect(identical(_profileEditorState(tester, finder), editorState), isTrue);
}

void _expectBioFocus(_FieldSnapshot bioDraft) {
  expect(bioDraft.focusNode.hasFocus, isTrue);
  expect(FocusManager.instance.primaryFocus, same(bioDraft.focusNode));
}

Future<void> _setLocaleAndPump(WidgetTester tester, AppLocale locale) async {
  I18n.setLocale(locale);
  await tester.pumpAndSettle();
}

Iterable<String?> _ancestorTooltipMessages(Finder target) {
  return find
      .ancestor(of: target, matching: find.byType(Tooltip))
      .evaluate()
      .map((element) => (element.widget as Tooltip).message);
}

Iterable<String?> _ancestorSemanticsLabels(Finder target) {
  return find
      .ancestor(of: target, matching: find.byType(Semantics))
      .evaluate()
      .map((element) => (element.widget as Semantics).properties.label);
}

Future<void> _openProfileFromMine(
  WidgetTester tester, {
  required String displayName,
}) async {
  final row = find.byKey(const ValueKey('mine_user_info_row'));
  final name = find.descendant(of: row, matching: find.text(displayName));
  expect(row, findsOneWidget);
  expect(name, findsOneWidget);
  await tester.tap(name);
  await tester.pumpAndSettle();
  expect(find.byType(ProfileScreen), findsOneWidget);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppLocale previousLocale;

  setUp(() {
    previousLocale = I18n.current;
    I18n.setLocale(AppLocale.zh);
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() => I18n.setLocale(previousLocale));

  testWidgets(
    'local Mine and Profile keep mounted locale, draft, and avatar routes',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final auth = AuthProvider(
        client: _testApiClient(
          token: '',
          handler: (_) async => http.Response('not found', 404),
        ),
      );
      final userProvider = UserProvider();
      addTearDown(auth.dispose);
      addTearDown(userProvider.dispose);
      await userProvider.updateProfile(
        username: 'local-user',
        displayName: 'Local display',
        email: 'local-before@example.test',
        avatarInitials: 'L',
        avatarUrl: 'Local avatar',
        bio: 'Local bio before',
      );

      await tester.pumpWidget(
        _wrapMine(auth: auth, userProvider: userProvider),
      );
      await tester.pumpAndSettle();

      final personalGroupZh = I18n.tr('mine.group.action_plan');
      await tester.scrollUntilVisible(
        find.text(personalGroupZh),
        260,
        scrollable: _mineListFinder(),
      );
      await tester.pumpAndSettle();
      expect(find.text(personalGroupZh), findsOneWidget);
      final mineListState = tester.state<ScrollableState>(_mineListFinder());
      final mineOffset = mineListState.position.pixels;

      await _setLocaleAndPump(tester, AppLocale.en);
      expect(find.text(I18n.tr('mine.group.action_plan')), findsOneWidget);
      expect(
        identical(
          tester.state<ScrollableState>(_mineListFinder()),
          mineListState,
        ),
        isTrue,
      );
      expect(mineListState.position.pixels, closeTo(mineOffset, 0.1));

      await _setLocaleAndPump(tester, AppLocale.zh);
      expect(find.text(personalGroupZh), findsOneWidget);
      expect(
        identical(
          tester.state<ScrollableState>(_mineListFinder()),
          mineListState,
        ),
        isTrue,
      );
      expect(mineListState.position.pixels, closeTo(mineOffset, 0.1));

      mineListState.position.jumpTo(0);
      await tester.pumpAndSettle();
      await _openProfileFromMine(tester, displayName: 'Local display');
      final profileRoute = ModalRoute.of(
        tester.element(find.byType(ProfileScreen)),
      );
      expect(profileRoute, isNotNull);

      final editorState = _profileEditorState(
        tester,
        _profileField('profile.display_name'),
      );
      final displayDraft = await _enterDraft(
        tester,
        key: 'profile.display_name',
        text: 'Draft display name',
        selection: const TextSelection(baseOffset: 2, extentOffset: 8),
      );
      final username = await _snapshotReadOnlyField(
        tester,
        'profile.local_nickname',
      );
      final emailDraft = await _enterDraft(
        tester,
        key: 'profile.email.local_display',
        text: 'draft@example.test',
        selection: const TextSelection.collapsed(offset: 7),
      );
      final bioDraft = await _enterDraft(
        tester,
        key: 'profile.bio',
        text: 'Draft local bio text',
        selection: const TextSelection(baseOffset: 6, extentOffset: 11),
      );
      expect(bioDraft.focusNode.hasFocus, isTrue);

      _expectBioFocus(bioDraft);
      await _setLocaleAndPump(tester, AppLocale.en);
      expect(bioDraft.focusNode.hasFocus, isTrue);
      expect(find.text(I18n.tr('profile.title')), findsOneWidget);
      expect(find.text(I18n.tr('action.save')), findsOneWidget);
      _expectFieldPreserved(
        tester,
        key: 'profile.display_name',
        snapshot: displayDraft,
        editorState: editorState,
      );
      _expectFieldPreserved(
        tester,
        key: 'profile.local_nickname',
        snapshot: username,
        editorState: editorState,
      );
      _expectFieldPreserved(
        tester,
        key: 'profile.email.local_display',
        snapshot: emailDraft,
        editorState: editorState,
      );
      _expectFieldPreserved(
        tester,
        key: 'profile.bio',
        snapshot: bioDraft,
        editorState: editorState,
        expectHasFocus: true,
      );
      expect(
        identical(
          ModalRoute.of(tester.element(find.byType(ProfileScreen))),
          profileRoute,
        ),
        isTrue,
      );
      expect(userProvider.profile.username, 'local-user');
      expect(userProvider.profile.displayName, 'Local display');
      expect(userProvider.profile.email, 'local-before@example.test');
      expect(userProvider.profile.bio, 'Local bio before');

      _expectBioFocus(bioDraft);
      await _setLocaleAndPump(tester, AppLocale.zh);
      expect(bioDraft.focusNode.hasFocus, isTrue);
      _expectFieldPreserved(
        tester,
        key: 'profile.display_name',
        snapshot: displayDraft,
        editorState: editorState,
      );
      _expectFieldPreserved(
        tester,
        key: 'profile.local_nickname',
        snapshot: username,
        editorState: editorState,
      );
      _expectFieldPreserved(
        tester,
        key: 'profile.email.local_display',
        snapshot: emailDraft,
        editorState: editorState,
      );
      _expectFieldPreserved(
        tester,
        key: 'profile.bio',
        snapshot: bioDraft,
        editorState: editorState,
        expectHasFocus: true,
      );

      _expectBioFocus(bioDraft);
      await _setLocaleAndPump(tester, AppLocale.en);
      expect(bioDraft.focusNode.hasFocus, isTrue);
      _expectFieldPreserved(
        tester,
        key: 'profile.bio',
        snapshot: bioDraft,
        editorState: editorState,
        expectHasFocus: true,
      );

      final previewButton = find.byKey(
        const ValueKey('profile_avatar_preview_button'),
      );
      final editButton = find.byKey(
        const ValueKey('profile_avatar_edit_button'),
      );
      await tester.ensureVisible(previewButton);
      await tester.pumpAndSettle();
      expect(_ancestorTooltipMessages(previewButton), contains('View avatar'));
      expect(_ancestorSemanticsLabels(previewButton), contains('View avatar'));
      expect(_ancestorTooltipMessages(editButton), contains('Edit avatar'));
      expect(_ancestorSemanticsLabels(editButton), contains('Edit avatar'));

      await tester.tapAt(
        tester.getTopLeft(previewButton) + const Offset(20, 20),
      );
      await tester.pumpAndSettle();
      final avatarViewer = find.byType(InteractiveViewer);
      expect(avatarViewer, findsOneWidget);
      final avatarRoute = ModalRoute.of(tester.element(avatarViewer));
      await _setLocaleAndPump(tester, AppLocale.zh);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(
        identical(
          ModalRoute.of(tester.element(find.byType(InteractiveViewer))),
          avatarRoute,
        ),
        isTrue,
      );
    },
  );

  testWidgets(
    'Mine avatar viewer localizes in place without opening Profile or editing',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final apiRequests = <http.Request>[];
      final auth = AuthProvider(
        client: _testApiClient(
          token: '',
          handler: (request) async {
            apiRequests.add(request);
            return http.Response('not found', 404);
          },
        ),
      );
      final userProvider = UserProvider();
      addTearDown(auth.dispose);
      addTearDown(userProvider.dispose);
      await userProvider.updateProfile(
        username: 'mine-avatar-user',
        displayName: 'Mine avatar display',
        email: 'mine-avatar@example.test',
        avatarInitials: 'M',
        avatarUrl: 'Mine avatar URL text',
        bio: 'Mine avatar bio',
      );

      await tester.pumpWidget(
        _wrapMine(auth: auth, userProvider: userProvider),
      );
      await tester.pumpAndSettle();
      final previewButton = find.byKey(
        const ValueKey('mine_avatar_preview_button'),
      );
      expect(previewButton, findsOneWidget);
      await tester.tap(previewButton);
      await tester.pumpAndSettle();

      expect(find.byType(ProfileScreen), findsNothing);
      final viewer = find.byType(InteractiveViewer);
      expect(viewer, findsOneWidget);
      final viewerState = _stateFor(tester, viewer);
      final avatarRoute = ModalRoute.of(tester.element(viewer));
      expect(find.text(I18n.tr('mine.avatar.title')), findsOneWidget);
      final editButton = find.byWidgetPredicate(
        (widget) =>
            widget is IconButton &&
            widget.tooltip == I18n.tr('mine.avatar.edit'),
      );
      expect(editButton, findsOneWidget);
      expect(
        tester.widget<IconButton>(editButton).tooltip,
        I18n.tr('mine.avatar.edit'),
      );

      await _setLocaleAndPump(tester, AppLocale.en);
      expect(find.text(I18n.tr('mine.avatar.title')), findsOneWidget);
      expect(
        tester.widget<IconButton>(editButton).tooltip,
        I18n.tr('mine.avatar.edit'),
      );
      expect(find.byType(ProfileScreen), findsNothing);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(identical(_stateFor(tester, viewer), viewerState), isTrue);
      expect(
        identical(ModalRoute.of(tester.element(viewer)), avatarRoute),
        isTrue,
      );
      expect(auth.state.isLoggedIn, isFalse);
      expect(userProvider.profile.displayName, 'Mine avatar display');
      expect(userProvider.profile.avatarUrl, 'Mine avatar URL text');
      expect(userProvider.profile.bio, 'Mine avatar bio');
      expect(apiRequests, isEmpty);
    },
  );

  testWidgets('signed-in Profile keeps display and bio drafts across locales', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final patchRequests = <http.Request>[];
    final auth = AuthProvider(
      initialState: const AuthState(
        userId: 'locale-user-1',
        username: 'stable-account-name',
        email: 'account@example.test',
        emailVerified: true,
        displayName: 'Account display before',
        bio: 'Account bio before',
        avatar: 'Account avatar',
        token: 'locale-token',
      ),
      client: _testApiClient(
        token: 'locale-token',
        handler: (request) async {
          if (request.method == 'PATCH' &&
              request.url.path == '/api/me/profile') {
            patchRequests.add(request);
          }
          return http.Response('not found', 404);
        },
      ),
    );
    final userProvider = UserProvider();
    addTearDown(auth.dispose);
    addTearDown(userProvider.dispose);
    await userProvider.applyAccountSnapshot(
      username: 'stable-account-name',
      displayName: 'Account display before',
      email: 'account@example.test',
      emailVerified: true,
      avatarUrl: 'Account avatar',
      bio: 'Account bio before',
    );

    await tester.pumpWidget(_wrapMine(auth: auth, userProvider: userProvider));
    await tester.pumpAndSettle();
    await _openProfileFromMine(tester, displayName: 'Account display before');
    final profileRoute = ModalRoute.of(
      tester.element(find.byType(ProfileScreen)),
    );
    final editorState = _profileEditorState(
      tester,
      _profileField('profile.nickname'),
    );

    final displayDraft = await _enterDraft(
      tester,
      key: 'profile.nickname',
      text: 'Draft account display',
      selection: const TextSelection(baseOffset: 2, extentOffset: 9),
    );
    final username = await _snapshotReadOnlyField(tester, 'auth.username');
    final bioDraft = await _enterDraft(
      tester,
      key: 'profile.bio',
      text: 'Draft account bio text',
      selection: const TextSelection(baseOffset: 1, extentOffset: 7),
    );

    _expectBioFocus(bioDraft);
    await _setLocaleAndPump(tester, AppLocale.en);
    expect(bioDraft.focusNode.hasFocus, isTrue);
    expect(find.text(I18n.tr('profile.title')), findsOneWidget);
    expect(find.text(I18n.tr('action.save')), findsOneWidget);
    _expectFieldPreserved(
      tester,
      key: 'profile.nickname',
      snapshot: displayDraft,
      editorState: editorState,
    );
    _expectFieldPreserved(
      tester,
      key: 'auth.username',
      snapshot: username,
      editorState: editorState,
    );
    _expectFieldPreserved(
      tester,
      key: 'profile.bio',
      snapshot: bioDraft,
      editorState: editorState,
      expectHasFocus: true,
    );
    expect(
      identical(
        ModalRoute.of(tester.element(find.byType(ProfileScreen))),
        profileRoute,
      ),
      isTrue,
    );
    expect(auth.state.displayName, 'Account display before');
    expect(auth.state.bio, 'Account bio before');
    expect(userProvider.profile.displayName, 'Account display before');
    expect(userProvider.profile.bio, 'Account bio before');
    expect(patchRequests, isEmpty);

    _expectBioFocus(bioDraft);
    await _setLocaleAndPump(tester, AppLocale.zh);
    expect(bioDraft.focusNode.hasFocus, isTrue);
    _expectFieldPreserved(
      tester,
      key: 'profile.nickname',
      snapshot: displayDraft,
      editorState: editorState,
    );
    _expectFieldPreserved(
      tester,
      key: 'auth.username',
      snapshot: username,
      editorState: editorState,
    );
    _expectFieldPreserved(
      tester,
      key: 'profile.bio',
      snapshot: bioDraft,
      editorState: editorState,
      expectHasFocus: true,
    );
    expect(find.text(I18n.tr('action.save')), findsOneWidget);
    expect(patchRequests, isEmpty);
  });

  testWidgets(
    'signed-in Profile localizes a rejected save without losing drafts or retrying',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final patchRequests = <http.Request>[];
      final auth = AuthProvider(
        initialState: const AuthState(
          userId: 'locale-error-user',
          username: 'locale-error-account',
          email: 'error@example.test',
          emailVerified: true,
          displayName: 'Error account display before',
          bio: 'Error account bio before',
          avatar: 'Account avatar',
          token: 'locale-error-token',
        ),
        client: _testApiClient(
          token: 'locale-error-token',
          handler: (request) async {
            if (request.method == 'PATCH' &&
                request.url.path == '/api/me/profile') {
              patchRequests.add(request);
              return http.Response(
                jsonEncode({'detail': '用户名或邮箱已被使用'}),
                409,
                headers: const {'content-type': 'application/json'},
              );
            }
            return http.Response('not found', 404);
          },
        ),
      );
      final userProvider = UserProvider();
      addTearDown(auth.dispose);
      addTearDown(userProvider.dispose);
      await userProvider.applyAccountSnapshot(
        username: 'locale-error-account',
        displayName: 'Error account display before',
        email: 'error@example.test',
        emailVerified: true,
        avatarUrl: 'Account avatar',
        bio: 'Error account bio before',
      );

      await tester.pumpWidget(
        _wrapMine(auth: auth, userProvider: userProvider),
      );
      await tester.pumpAndSettle();
      await _openProfileFromMine(
        tester,
        displayName: 'Error account display before',
      );
      final profileRoute = ModalRoute.of(
        tester.element(find.byType(ProfileScreen)),
      );
      final editorState = _profileEditorState(
        tester,
        _profileField('profile.nickname'),
      );
      final displayDraft = await _enterDraft(
        tester,
        key: 'profile.nickname',
        text: 'Rejected display draft',
        selection: const TextSelection(baseOffset: 2, extentOffset: 10),
      );
      final bioDraft = await _enterDraft(
        tester,
        key: 'profile.bio',
        text: 'Rejected bio draft',
        selection: const TextSelection(baseOffset: 1, extentOffset: 8),
      );

      final saveButton = find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(FilledButton),
      );
      expect(saveButton, findsOneWidget);
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(patchRequests, hasLength(1));
      expect(patchRequests.single.method, 'PATCH');
      final errorBannerZh = _profileBanner(
        title: I18n.tr('profile.save_failed'),
        message: '用户名或邮箱已被使用，请更换后重试',
      );
      expect(errorBannerZh, findsOneWidget);
      await tester.ensureVisible(errorBannerZh);
      await tester.pumpAndSettle();
      expect(auth.state.displayName, 'Error account display before');
      expect(auth.state.bio, 'Error account bio before');

      await _setLocaleAndPump(tester, AppLocale.en);
      final errorBannerEn = _profileBanner(
        title: I18n.tr('profile.save_failed'),
        message: 'Username or email is already in use. Please choose another.',
      );
      expect(errorBannerEn, findsOneWidget);
      _expectFieldPreserved(
        tester,
        key: 'profile.nickname',
        snapshot: displayDraft,
        editorState: editorState,
      );
      _expectFieldPreserved(
        tester,
        key: 'profile.bio',
        snapshot: bioDraft,
        editorState: editorState,
      );
      expect(
        identical(
          ModalRoute.of(tester.element(find.byType(ProfileScreen))),
          profileRoute,
        ),
        isTrue,
      );
      expect(patchRequests, hasLength(1));
      expect(auth.state.displayName, 'Error account display before');
      expect(auth.state.bio, 'Error account bio before');
    },
  );

  testWidgets(
    'email code feedback and cooldown survive a locale change without resending',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final codeRequests = <http.Request>[];
      final auth = AuthProvider(
        initialState: const AuthState(
          userId: 'locale-email-user',
          username: 'locale-email-account',
          email: '',
          emailVerified: false,
          displayName: 'Email account display',
          bio: 'Email account bio',
          avatar: 'Account avatar',
          token: 'locale-email-token',
        ),
        client: _testApiClient(
          token: 'locale-email-token',
          handler: (request) async {
            if (request.method == 'POST' &&
                request.url.path == '/api/me/email-code') {
              codeRequests.add(request);
              final isCanonicalResponse = codeRequests.length == 1;
              return http.Response(
                jsonEncode({
                  'message': isCanonicalResponse
                      ? '验证码已发送，请查看邮箱。'
                      : 'Custom mail gateway accepted the request.',
                  'dev_code': isCanonicalResponse ? '246810' : '975310',
                }),
                200,
                headers: const {'content-type': 'application/json'},
              );
            }
            return http.Response('not found', 404);
          },
        ),
      );
      final userProvider = UserProvider();
      addTearDown(auth.dispose);
      addTearDown(userProvider.dispose);
      await userProvider.applyAccountSnapshot(
        username: 'locale-email-account',
        displayName: 'Email account display',
        email: '',
        emailVerified: false,
        avatarUrl: 'Account avatar',
        bio: 'Email account bio',
      );

      await tester.pumpWidget(
        _wrapMine(auth: auth, userProvider: userProvider),
      );
      await tester.pumpAndSettle();
      await _openProfileFromMine(tester, displayName: 'Email account display');
      final bindButton = find.widgetWithText(
        TextButton,
        I18n.tr('profile.email.binding'),
      );
      expect(bindButton, findsOneWidget);
      await tester.tap(bindButton);
      await tester.pumpAndSettle();

      final emailField = _textFieldWithLabel(I18n.tr('auth.email'));
      final codeField = _textFieldWithLabel(I18n.tr('auth.email_code'));
      expect(emailField, findsOneWidget);
      expect(codeField, findsOneWidget);
      final emailController = tester.widget<TextField>(emailField).controller!;
      final codeController = tester.widget<TextField>(codeField).controller!;
      await tester.enterText(emailField, 'next@example.test');
      await tester.enterText(codeField, 'saved-input-code');
      await tester.pump();

      final sendButton = find.widgetWithText(
        FilledButton,
        I18n.tr('auth.send'),
      );
      expect(sendButton, findsOneWidget);
      await tester.tap(sendButton);
      await tester.pumpAndSettle();

      expect(codeRequests, hasLength(1));
      expect(codeRequests.single.url.path, '/api/me/email-code');
      expect(jsonDecode(codeRequests.single.body), {
        'email': 'next@example.test',
        'purpose': 'bind',
      });
      expect(
        _profileBanner(
          title: I18n.tr('profile.saved'),
          message:
              '${I18n.tr('auth.email_code.sent_check_email')} ${I18n.tr('auth.email_code.code_prefix')}246810',
        ),
        findsOneWidget,
      );
      final cooldown = find.ancestor(
        of: _cooldownLabel(),
        matching: find.byType(FilledButton),
      );
      expect(cooldown, findsOneWidget);
      expect(tester.widget<FilledButton>(cooldown).onPressed, isNull);

      await _setLocaleAndPump(tester, AppLocale.en);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(I18n.tr('profile.email.binding')),
        ),
        findsWidgets,
      );
      expect(
        _profileBanner(
          title: I18n.tr('profile.saved'),
          message:
              '${I18n.tr('auth.email_code.sent_check_email')} ${I18n.tr('auth.email_code.code_prefix')}246810',
        ),
        findsOneWidget,
      );
      expect(
        identical(
          tester
              .widget<TextField>(_textFieldWithLabel(I18n.tr('auth.email')))
              .controller,
          emailController,
        ),
        isTrue,
      );
      expect(emailController.text, 'next@example.test');
      expect(
        identical(
          tester
              .widget<TextField>(
                _textFieldWithLabel(I18n.tr('auth.email_code')),
              )
              .controller,
          codeController,
        ),
        isTrue,
      );
      expect(codeController.text, 'saved-input-code');
      final cooldownAfterLocaleChange = find.ancestor(
        of: _cooldownLabel(),
        matching: find.byType(FilledButton),
      );
      expect(cooldownAfterLocaleChange, findsOneWidget);
      expect(
        tester.widget<FilledButton>(cooldownAfterLocaleChange).onPressed,
        isNull,
      );
      expect(codeRequests, hasLength(1));
    },
  );

  testWidgets(
    'email code keeps an unrecognized server message and code across locales',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final codeRequests = <http.Request>[];
      final auth = AuthProvider(
        initialState: const AuthState(
          userId: 'locale-custom-email-user',
          username: 'locale-custom-email-account',
          email: '',
          emailVerified: false,
          displayName: 'Custom email account display',
          bio: 'Custom email account bio',
          avatar: 'Account avatar',
          token: 'locale-custom-email-token',
        ),
        client: _testApiClient(
          token: 'locale-custom-email-token',
          handler: (request) async {
            if (request.method == 'POST' &&
                request.url.path == '/api/me/email-code') {
              codeRequests.add(request);
              return http.Response(
                jsonEncode({
                  'message': 'Custom mail gateway accepted the request.',
                  'dev_code': '975310',
                }),
                200,
                headers: const {'content-type': 'application/json'},
              );
            }
            return http.Response('not found', 404);
          },
        ),
      );
      final userProvider = UserProvider();
      addTearDown(auth.dispose);
      addTearDown(userProvider.dispose);
      await userProvider.applyAccountSnapshot(
        username: 'locale-custom-email-account',
        displayName: 'Custom email account display',
        email: '',
        emailVerified: false,
        avatarUrl: 'Account avatar',
        bio: 'Custom email account bio',
      );

      await tester.pumpWidget(
        _wrapMine(auth: auth, userProvider: userProvider),
      );
      await tester.pumpAndSettle();
      await _openProfileFromMine(
        tester,
        displayName: 'Custom email account display',
      );
      await tester.tap(
        find.widgetWithText(TextButton, I18n.tr('profile.email.binding')),
      );
      await tester.pumpAndSettle();
      final emailField = _textFieldWithLabel(I18n.tr('auth.email'));
      final codeField = _textFieldWithLabel(I18n.tr('auth.email_code'));
      await tester.enterText(emailField, 'custom@example.test');
      await tester.enterText(codeField, 'input-code-fact');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, I18n.tr('auth.send')));
      await tester.pumpAndSettle();

      expect(codeRequests, hasLength(1));
      expect(
        _profileBanner(
          title: I18n.tr('profile.saved'),
          message: 'Custom mail gateway accepted the request. 验证码：975310',
        ),
        findsOneWidget,
      );
      await _setLocaleAndPump(tester, AppLocale.en);
      expect(
        _profileBanner(
          title: I18n.tr('profile.saved'),
          message: 'Custom mail gateway accepted the request. Code: 975310',
        ),
        findsOneWidget,
      );
      expect(codeRequests, hasLength(1));
    },
  );

  testWidgets(
    'signed-in Profile keeps a pending save alive across locale change',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final responseGate = Completer<http.Response>();
      final requestStarted = Completer<void>();
      final patchRequests = <http.Request>[];
      final patchBodies = <Map<String, dynamic>>[];
      final auth = AuthProvider(
        initialState: const AuthState(
          userId: 'locale-save-user',
          username: 'locale-save-account',
          email: 'save@example.test',
          emailVerified: true,
          displayName: 'Saved account display before',
          bio: 'Saved account bio before',
          avatar: 'Account avatar',
          token: 'locale-save-token',
        ),
        client: _testApiClient(
          token: 'locale-save-token',
          handler: (request) async {
            if (request.method == 'PATCH' &&
                request.url.path == '/api/me/profile') {
              patchRequests.add(request);
              patchBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
              if (!requestStarted.isCompleted) requestStarted.complete();
              return responseGate.future;
            }
            return http.Response('not found', 404);
          },
        ),
      );
      final userProvider = UserProvider();
      addTearDown(auth.dispose);
      addTearDown(userProvider.dispose);
      await userProvider.applyAccountSnapshot(
        username: 'locale-save-account',
        displayName: 'Saved account display before',
        email: 'save@example.test',
        emailVerified: true,
        avatarUrl: 'Account avatar',
        bio: 'Saved account bio before',
      );

      await tester.pumpWidget(
        _wrapMine(auth: auth, userProvider: userProvider),
      );
      await tester.pumpAndSettle();
      await _openProfileFromMine(
        tester,
        displayName: 'Saved account display before',
      );
      final profileRoute = ModalRoute.of(
        tester.element(find.byType(ProfileScreen)),
      );
      final editorState = _profileEditorState(
        tester,
        _profileField('profile.nickname'),
      );
      final displayDraft = await _enterDraft(
        tester,
        key: 'profile.nickname',
        text: 'Pending account display',
        selection: const TextSelection(baseOffset: 2, extentOffset: 9),
      );
      final bioDraft = await _enterDraft(
        tester,
        key: 'profile.bio',
        text: 'Pending account bio',
        selection: const TextSelection(baseOffset: 1, extentOffset: 7),
      );

      final saveButton = find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(FilledButton),
      );
      expect(saveButton, findsOneWidget);
      await tester.tap(find.text(I18n.tr('action.save')));
      await tester.pump();
      await tester.pump();

      expect(requestStarted.isCompleted, isTrue);
      expect(patchRequests, hasLength(1));
      expect(patchBodies.single, {
        'display_name': 'Pending account display',
        'displayName': 'Pending account display',
        'bio': 'Pending account bio',
      });
      expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);
      expect(
        find.descendant(
          of: saveButton,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(auth.state.displayName, 'Saved account display before');
      expect(auth.state.bio, 'Saved account bio before');

      I18n.setLocale(AppLocale.en);
      await tester.pump();
      expect(find.text(I18n.tr('profile.title')), findsOneWidget);
      expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);
      expect(
        find.descendant(
          of: saveButton,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(patchRequests, hasLength(1));
      _expectFieldPreserved(
        tester,
        key: 'profile.nickname',
        snapshot: displayDraft,
        editorState: editorState,
      );
      _expectFieldPreserved(
        tester,
        key: 'profile.bio',
        snapshot: bioDraft,
        editorState: editorState,
      );
      expect(
        identical(
          ModalRoute.of(tester.element(find.byType(ProfileScreen))),
          profileRoute,
        ),
        isTrue,
      );
      expect(auth.state.displayName, 'Saved account display before');
      expect(auth.state.bio, 'Saved account bio before');

      responseGate.complete(
        http.Response(
          jsonEncode({
            'user': {
              'user_id': 'locale-save-user',
              'username': 'locale-save-account',
              'email': 'save@example.test',
              'email_verified': true,
              'display_name': 'Pending account display',
              'bio': 'Pending account bio',
              'avatar': 'Account avatar',
            },
          }),
          200,
          headers: const {'content-type': 'application/json'},
        ),
      );
      await tester.pumpAndSettle();

      expect(patchRequests, hasLength(1));
      expect(auth.state.displayName, 'Pending account display');
      expect(auth.state.bio, 'Pending account bio');
      expect(userProvider.profile.displayName, 'Pending account display');
      expect(userProvider.profile.bio, 'Pending account bio');
      expect(find.text(I18n.tr('action.save')), findsOneWidget);

      final successBanner = _profileBanner(
        title: I18n.tr('profile.saved'),
        message: I18n.tr('profile.updated'),
      );
      expect(successBanner, findsOneWidget);
      await tester.ensureVisible(successBanner);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text(I18n.tr('profile.updated')),
        ),
        findsOneWidget,
      );

      await _setLocaleAndPump(tester, AppLocale.zh);
      expect(
        _profileBanner(
          title: I18n.tr('profile.saved'),
          message: I18n.tr('profile.updated'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text(I18n.tr('profile.updated')),
        ),
        findsOneWidget,
      );
      expect(patchRequests, hasLength(1));

      await _setLocaleAndPump(tester, AppLocale.en);
      expect(
        _profileBanner(
          title: I18n.tr('profile.saved'),
          message: I18n.tr('profile.updated'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text(I18n.tr('profile.updated')),
        ),
        findsOneWidget,
      );
      expect(patchRequests, hasLength(1));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
