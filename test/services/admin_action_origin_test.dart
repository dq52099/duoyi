import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/admin_action_origin.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/services/app_update_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  tearDown(() => I18n.setLocale(AppLocale.zh));

  testWidgets('language/profile changes preserve rendered authority', (
    tester,
  ) async {
    final fixture = await _Fixture.pump(tester);
    final origin = fixture.capture();
    I18n.setLocale(AppLocale.en);
    fixture.auth.change(fixture.auth.state.copyWith(displayName: 'literal'));
    await tester.pumpAndSettle();
    expect(origin.isCurrent(), isTrue);
    I18n.setLocale(AppLocale.zh);
    await tester.pumpAndSettle();
    expect(origin.isCurrent(), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final change in [
    'permission',
    'admin',
    'token',
    'account',
    'transition',
    'blocked',
    'lock',
    'update',
  ]) {
    testWidgets('$change changes cannot revive an old receipt without a pump', (
      tester,
    ) async {
      final fixture = await _Fixture.pump(tester);
      final origin = fixture.capture();
      final original = fixture.auth.state;
      switch (change) {
        case 'permission':
          fixture.auth.change(original.copyWith(adminPermissions: ['users']));
          fixture.auth.change(original);
        case 'admin':
          fixture.auth.change(original.copyWith(isAdmin: false));
          fixture.auth.change(original);
        case 'token':
          fixture.auth.change(original.copyWith(token: 'synthetic-other'));
          fixture.auth.change(original);
        case 'account':
          fixture.auth.change(original.copyWith(userId: 'other'));
          fixture.auth.change(original);
        case 'transition':
          fixture.auth.transition(true);
          fixture.auth.transition(false);
        case 'blocked':
          fixture.auth.block(true);
          fixture.auth.block(false);
        case 'lock':
          fixture.lock.change(true);
          fixture.lock.change(false);
        case 'update':
          fixture.update.change(true);
          fixture.update.change(false);
      }
      expect(origin.isCurrent(checkRoute: false), isFalse);
      await tester.pumpAndSettle();
      expect(fixture.capture().isCurrent(), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final permissions in <List<String>?>[
    null,
    ['*'],
    ['groups'],
    ['users'],
    ['coins'],
    ['__none__', '*'],
    ['__none__', 'groups'],
    [],
  ]) {
    testWidgets('read and write authority for $permissions', (tester) async {
      final fixture = await _Fixture.pump(tester, permissions: permissions);
      final write = fixture.capture();
      final read = fixture.capture(read: true);
      final all =
          permissions == null ||
          (!permissions.contains('__none__') && permissions.contains('*'));
      expect(
        write.isCurrent(),
        all ||
            (!permissions.contains('__none__') &&
                permissions.contains('groups')),
      );
      expect(
        read.isCurrent(),
        all ||
            (!permissions.contains('__none__') &&
                permissions.any(['groups', 'users', 'coins'].contains)),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final field in ['token', 'baseUrl']) {
    testWidgets(
      'mutable client $field invalidates receipt even without notify',
      (tester) async {
        final fixture = await _Fixture.pump(tester);
        final origin = fixture.capture();
        if (field == 'token') {
          fixture.auth.client.token = 'synthetic-new';
        } else {
          fixture.auth.client.baseUrl = 'https://other.test';
        }
        expect(origin.isCurrent(), isFalse);
        expect(origin.isCurrent(checkRoute: false), isFalse);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('replacing Auth provider invalidates captured authority', (
    tester,
  ) async {
    final fixture = await _Fixture.pump(tester);
    final origin = fixture.capture();
    final replacement = _Auth(const ['groups']);
    addTearDown(replacement.dispose);
    await fixture.render(tester, replacement);
    expect(origin.isCurrent(), isFalse);
    expect(
      fixture.host.currentState!.capture(replacement.client).isCurrent(),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('own dialog permits only noncurrent caller checks', (
    tester,
  ) async {
    final fixture = await _Fixture.pump(tester);
    final allowed = fixture.capture();
    final covered = fixture.capture();
    final pending = showDialog<void>(
      context: fixture.host.currentContext!,
      builder: (context) =>
          const AlertDialog(content: Text('Synthetic dialog')),
    );
    await tester.pumpAndSettle();
    expect(allowed.isCurrent(checkRoute: false), isTrue);
    expect(covered.isCurrent(), isFalse);
    fixture.navigator.currentState!.pop();
    await pending;
    await tester.pumpAndSettle();
    expect(allowed.isCurrent(), isTrue);
    expect(covered.isCurrent(), isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(allowed.isCurrent(), isFalse);
  });

  testWidgets('account data generation invalidates retained authority', (
    tester,
  ) async {
    final fixture = await _Fixture.pump(tester);
    final origin = fixture.capture();
    AccountLocalDataCleaner.invalidateInFlightAccountWrites();
    expect(origin.isCurrent(), isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _Fixture {
  _Fixture(List<String>? permissions) : auth = _Auth(permissions);
  final _Auth auth;
  final lock = _Lock();
  final update = _Update();
  final host = GlobalKey<_HostState>();
  final navigator = GlobalKey<NavigatorState>();

  static Future<_Fixture> pump(
    WidgetTester tester, {
    List<String>? permissions = const ['groups'],
  }) async {
    final fixture = _Fixture(permissions);
    addTearDown(fixture.auth.dispose);
    addTearDown(fixture.lock.dispose);
    addTearDown(fixture.update.dispose);
    await fixture.render(tester, fixture.auth);
    return fixture;
  }

  Future<void> render(WidgetTester tester, _Auth auth) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<AppLockProvider>.value(value: lock),
          ChangeNotifierProvider<AppUpdateService>.value(value: update),
        ],
        child: MaterialApp(
          navigatorKey: navigator,
          home: _Host(key: host),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  AdminActionOrigin capture({bool read = false}) =>
      host.currentState!.capture(auth.client, read: read);
}

class _Host extends StatefulWidget {
  const _Host({super.key});
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  final originHost = AdminActionHost();
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    originHost.bind(context);
  }

  AdminActionOrigin capture(ApiClient client, {bool read = false}) =>
      originHost.capture(
        client: client,
        anyOfPermissions: read
            ? const {'groups', 'users', 'coins'}
            : const {'groups'},
      );

  @override
  void dispose() {
    originHost.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Text('Admin host'));
}

class _Auth extends AuthProvider {
  _Auth(List<String>? permissions)
    : super(
        client: ApiClient(
          baseUrl: 'https://duoyi.test',
          token: 'synthetic-admin',
        ),
        initialState: AuthState(
          userId: 'admin',
          token: 'synthetic-admin',
          isAdmin: true,
          adminPermissions: permissions,
        ),
      ) {
    current = super.state;
  }
  late AuthState current;
  bool transitioning = false;
  bool blocked = false;
  @override
  AuthState get state => current;
  @override
  bool get isAccountTransitionInProgress => transitioning;
  @override
  bool get isLocalAccountDataBlocked => blocked;
  void change(AuthState next) {
    current = next;
    client.token = next.token;
    notifyListeners();
  }

  void transition(bool value) {
    transitioning = value;
    notifyListeners();
  }

  void block(bool value) {
    blocked = value;
    notifyListeners();
  }
}

class _Lock extends AppLockProvider {
  bool locked = false;
  @override
  bool get isLocked => locked;
  void change(bool value) {
    locked = value;
    notifyListeners();
  }
}

class _Update extends AppUpdateService {
  _Update() : super(repo: 'synthetic/duoyi', currentVersion: '0.0.0');
  bool requiredUpdate = false;
  @override
  bool get mustUpdate => requiredUpdate;
  void change(bool value) {
    requiredUpdate = value;
    notifyListeners();
  }
}
