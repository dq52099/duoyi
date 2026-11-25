import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/core/todo_board_ui_copy.dart';
import 'package:duoyi/models/todo.dart';
import 'package:duoyi/models/workspace.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/app_lock_provider.dart';
import 'package:duoyi/providers/goal_provider.dart';
import 'package:duoyi/providers/habit_provider.dart';
import 'package:duoyi/providers/share_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/providers/todo_provider.dart';
import 'package:duoyi/screens/todo_screen.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/app_access_route_gate.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/weekly_review_screenshot_font.dart';

const _userId = 'share-user';
const _groupName = '项目清单';
const _sourceWorkspaceId = 'source-workspace';
const _targetWorkspaceId = 'target-workspace';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.zh);
  });

  tearDown(() => I18n.setLocale(AppLocale.zh));

  test('both list group row implementations wire the sharing button', () {
    final source = File('lib/screens/todo_screen.dart').readAsStringSync();
    final headerStart = source.indexOf('class _ListGroupHeader');
    final legacyStart = source.indexOf('class _ListGroupTileState');
    final legacyBodyEnd = source.indexOf('Widget _buildTodoList', legacyStart);

    expect(headerStart, greaterThanOrEqualTo(0));
    expect(legacyStart, greaterThan(headerStart));
    expect(legacyBodyEnd, greaterThan(legacyStart));
    expect(
      source.substring(headerStart, legacyStart),
      contains('_ListGroupShareButton(groupName:'),
    );
    expect(
      source.substring(legacyStart, legacyBodyEnd),
      contains('_ListGroupShareButton(groupName:'),
    );
  });

  for (final replacementKind in ['Auth', 'Todo', 'Share']) {
    testWidgets(
      '$replacementKind provider replacement revokes a retained opener and fresh sharing works',
      (tester) async {
        final originalItems = [
          _todo('provider-task-a', 'Provider task A'),
          _todo('provider-task-b', 'Provider task B'),
        ];
        final originalTodos = await _hydratedTodos(originalItems);
        final originalShare = _FixtureShareProvider(
          workspaces: [_workspace(_targetWorkspaceId, 'Team space')],
        );
        final originalAuth = _auth();
        final fixture = _TodoFixture(
          todos: originalTodos,
          auth: originalAuth,
          share: originalShare,
        );
        await fixture.mount(tester);
        _registerCleanup(tester, fixture);

        final screenElement = tester.element(find.byType(TodoScreen));
        final navigatorState = fixture.navigatorKey.currentState;
        final retainedOpener = _captureShareOpener(tester);
        final replacementTodos = replacementKind == 'Todo'
            ? await _hydratedTodos(originalItems)
            : originalTodos;
        final replacementShare = replacementKind == 'Share'
            ? _FixtureShareProvider(
                workspaces: [_workspace(_targetWorkspaceId, 'Team space')],
              )
            : originalShare;
        final replacementAuth = replacementKind == 'Auth'
            ? _auth()
            : originalAuth;
        fixture.replaceProviders(
          todos: replacementTodos,
          share: replacementShare,
          auth: replacementAuth,
        );
        await tester.pumpAndSettle();

        expect(tester.element(find.byType(TodoScreen)), same(screenElement));
        expect(fixture.navigatorKey.currentState, same(navigatorState));
        retainedOpener();
        await tester.pumpAndSettle();
        expect(find.text(TodoBoardUiCopy.shareListDialogTitle), findsNothing);
        expect(originalTodos.updates, isEmpty);
        expect(replacementTodos.updates, isEmpty);

        final replacementMembersBeforeSave = {
          for (final item in replacementTodos.todos) item.id: item,
        };
        await _openShareSheet(tester);
        await tester.tap(_workspaceTileFinder(tester, 'Team space'));
        await tester.pumpAndSettle();

        if (!identical(originalTodos, replacementTodos)) {
          expect(originalTodos.updates, isEmpty);
        }
        expect(replacementTodos.updates, hasLength(1));
        final update = replacementTodos.updates.single;
        expect(update.groupName, _groupName);
        expect(update.workspaceId, _targetWorkspaceId);
        expect(update.userId, _userId);
        expect(
          update.expectedAccountDataGeneration,
          AccountLocalDataCleaner.accountDataGeneration,
        );
        expect(update.expectedGroupMembers!.keys.toSet(), {
          'provider-task-a',
          'provider-task-b',
        });
        for (final item in replacementTodos.todos) {
          expect(item.workspaceId, _targetWorkspaceId);
        }
        for (final entry in replacementMembersBeforeSave.entries) {
          expect(update.expectedGroupMembers![entry.key], same(entry.value));
        }
        expect(replacementShare.loadCount, 0);
      },
    );
  }

  testWidgets('account invalidation during workspace load blocks the sheet', (
    tester,
  ) async {
    final todos = await _hydratedTodos([_todo('account-task', 'Account task')]);
    final loadGate = Completer<void>();
    final share = _FixtureShareProvider(
      loadGate: loadGate,
      workspacesAfterLoad: [_workspace(_targetWorkspaceId, 'Team space')],
    );
    final fixture = _TodoFixture(todos: todos, auth: _auth(), share: share);
    await fixture.mount(tester);
    _registerCleanup(tester, fixture);

    await tester.tap(_shareButtonFinder(tester));
    await tester.pump();
    expect(share.loadCount, 1);
    expect(find.text(TodoBoardUiCopy.shareListDialogTitle), findsNothing);

    AccountLocalDataCleaner.invalidateInFlightAccountWrites();
    loadGate.complete();
    await tester.pumpAndSettle();

    expect(share.workspaces, hasLength(1));
    expect(find.text(TodoBoardUiCopy.shareListDialogTitle), findsNothing);
    expect(todos.updates, isEmpty);
  });

  testWidgets('covered share sheet callbacks cannot select or pop the cover', (
    tester,
  ) async {
    final todos = await _hydratedTodos([_todo('covered-task', 'Covered task')]);
    final share = _FixtureShareProvider(
      workspaces: [_workspace(_targetWorkspaceId, 'Team space')],
    );
    final fixture = _TodoFixture(todos: todos, auth: _auth(), share: share);
    await fixture.mount(tester);
    _registerCleanup(tester, fixture);

    await _openShareSheet(tester);
    final retainedSelection = _workspaceTileAction(tester, 'Team space');
    final retainedPrivate = _workspaceTileAction(
      tester,
      TodoBoardUiCopy.onlyMyselfVisible,
    );
    fixture.navigatorKey.currentState!
        .push<void>(
          MaterialPageRoute<void>(
            builder: (_) =>
                const Scaffold(body: Center(child: Text('covering route'))),
          ),
        )
        .then<void>((_) {});
    await tester.pumpAndSettle();

    expect(find.text('covering route'), findsOneWidget);
    retainedPrivate();
    retainedSelection();
    await tester.pumpAndSettle();
    expect(find.text('covering route'), findsOneWidget);
    expect(todos.updates, isEmpty);

    fixture.navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    retainedPrivate();
    retainedSelection();
    await tester.pumpAndSettle();
    expect(find.text('covering route'), findsNothing);
    expect(find.text(TodoBoardUiCopy.shareListDialogTitle), findsNothing);
    expect(todos.updates, isEmpty);
  });

  for (final revocation in ['lock', 'session', 'source role']) {
    testWidgets('$revocation permanently revokes an open sharing operation', (
      tester,
    ) async {
      final todos = await _hydratedTodos([
        _todo(
          'revoked-task',
          'Task to protect',
          workspaceId: _sourceWorkspaceId,
        ),
      ]);
      final share = _FixtureShareProvider(
        workspaces: [
          _workspace(_sourceWorkspaceId, 'Source space'),
          _workspace(_targetWorkspaceId, 'Team space'),
        ],
      );
      final auth = _RotatingAuth();
      final lock = AppLockProvider();
      expect(await lock.setPin('2468'), isTrue);
      final fixture = _TodoFixture(
        todos: todos,
        auth: auth,
        share: share,
        lock: lock,
      );
      await fixture.mount(tester);
      _registerCleanup(tester, fixture);
      await _openShareSheet(tester);
      final retained = _workspaceTileAction(tester, 'Team space');
      if (revocation == 'lock') {
        lock.lock();
        await lock.unlockWith('2468');
      } else if (revocation == 'session') {
        auth.rotateSession();
      } else {
        share.setWorkspaces([
          _workspace(
            _sourceWorkspaceId,
            'Source space',
            role: WorkspaceRole.viewer,
          ),
          _workspace(_targetWorkspaceId, 'Team space'),
        ]);
      }
      await tester.pumpAndSettle();
      share.setWorkspaces([
        _workspace(_sourceWorkspaceId, 'Source space'),
        _workspace(_targetWorkspaceId, 'Team space'),
      ]);
      await tester.pumpAndSettle();
      retained();
      await tester.pumpAndSettle();
      expect(todos.updates, isEmpty);
      expect(todos.todos.single.workspaceId, _sourceWorkspaceId);
      expect(find.text(TodoBoardUiCopy.shareStatusUpdated), findsNothing);
      await _openShareSheet(tester);
      await tester.tap(_workspaceTileFinder(tester, 'Team space'));
      await tester.pumpAndSettle();
      expect(todos.updates, hasLength(1));
      expect(todos.todos.single.workspaceId, _targetWorkspaceId);
    });
  }

  testWidgets('workspace edit downgrade rejects a retained selection', (
    tester,
  ) async {
    final todos = await _hydratedTodos([
      _todo('permission-task', 'Permission task'),
    ]);
    final editorWorkspace = _workspace(_targetWorkspaceId, 'Team space');
    final share = _FixtureShareProvider(workspaces: [editorWorkspace]);
    final fixture = _TodoFixture(todos: todos, auth: _auth(), share: share);
    await fixture.mount(tester);
    _registerCleanup(tester, fixture);

    await _openShareSheet(tester);
    final retainedSelection = _workspaceTileAction(tester, 'Team space');
    share.setWorkspaces([
      _workspace(_targetWorkspaceId, 'Team space', role: WorkspaceRole.viewer),
    ]);
    await tester.pumpAndSettle();
    expect(_workspaceTile(tester, 'Team space').enabled, isFalse);

    retainedSelection();
    await tester.pumpAndSettle();
    expect(todos.updates, isEmpty);
    expect(find.text(TodoBoardUiCopy.shareListDialogTitle), findsOneWidget);

    share.setWorkspaces([editorWorkspace]);
    await tester.pumpAndSettle();
    await tester.tap(_workspaceTileFinder(tester, 'Team space'));
    await tester.pumpAndSettle();
    expect(todos.updates, hasLength(1));
    expect(todos.todos.single.workspaceId, _targetWorkspaceId);
  });

  testWidgets('removing a target workspace rejects a retained selection', (
    tester,
  ) async {
    final todos = await _hydratedTodos([_todo('removed-task', 'Removed task')]);
    final workspace = _workspace(_targetWorkspaceId, 'Team space');
    final share = _FixtureShareProvider(workspaces: [workspace]);
    final fixture = _TodoFixture(todos: todos, auth: _auth(), share: share);
    await fixture.mount(tester);
    _registerCleanup(tester, fixture);

    await _openShareSheet(tester);
    final retainedSelection = _workspaceTileAction(tester, 'Team space');
    share.setWorkspaces(const []);
    await tester.pumpAndSettle();
    expect(_workspaceTileFinder(tester, 'Team space'), findsNothing);

    retainedSelection();
    await tester.pumpAndSettle();
    expect(todos.updates, isEmpty);
    expect(find.text(TodoBoardUiCopy.shareListDialogTitle), findsOneWidget);
  });

  testWidgets('same-name group content reuse rejects its retained opener', (
    tester,
  ) async {
    final original = _todo('reused-group-task', 'Original content');
    final todos = await _hydratedTodos([original]);
    final share = _FixtureShareProvider(
      workspaces: [_workspace(_targetWorkspaceId, 'Team space')],
    );
    final fixture = _TodoFixture(todos: todos, auth: _auth(), share: share);
    await fixture.mount(tester);
    _registerCleanup(tester, fixture);

    final retainedOpener = _captureShareOpener(tester);
    final replacement = _todo('reused-group-task', 'Changed content');
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('todos', jsonEncode([replacement.toJson()]));
    await todos.loadFromStorage(force: true);
    await tester.pumpAndSettle();
    expect(find.text('Changed content'), findsOneWidget);

    retainedOpener();
    await tester.pumpAndSettle();
    expect(find.text(TodoBoardUiCopy.shareListDialogTitle), findsNothing);
    expect(todos.updates, isEmpty);

    final replacementMember = todos.todos.single;
    await _openShareSheet(tester);
    await tester.tap(_workspaceTileFinder(tester, 'Team space'));
    await tester.pumpAndSettle();
    expect(todos.updates, hasLength(1));
    expect(
      todos.updates.single.expectedGroupMembers!['reused-group-task'],
      same(replacementMember),
    );
  });

  testWidgets(
    'empty workspace cache loads before sharing an already shared source',
    (tester) async {
      final todos = await _hydratedTodos([
        _todo(
          'already-shared-task',
          'Already shared task',
          workspaceId: _sourceWorkspaceId,
        ),
      ]);
      final share = _FixtureShareProvider(
        workspacesAfterLoad: [
          _workspace(_sourceWorkspaceId, 'Current space'),
          _workspace(_targetWorkspaceId, 'New space'),
        ],
      );
      final fixture = _TodoFixture(todos: todos, auth: _auth(), share: share);
      await fixture.mount(tester);
      _registerCleanup(tester, fixture);

      expect(share.workspaces, isEmpty);
      await tester.tap(_shareButtonFinder(tester));
      await tester.pumpAndSettle();

      expect(share.loadCount, 1);
      expect(find.text(TodoBoardUiCopy.shareListDialogTitle), findsOneWidget);
      expect(_workspaceTileFinder(tester, 'Current space'), findsOneWidget);
      expect(_workspaceTileFinder(tester, 'New space'), findsOneWidget);
      await tester.tap(_workspaceTileFinder(tester, 'New space'));
      await tester.pumpAndSettle();
      expect(todos.updates, hasLength(1));
      expect(todos.todos.single.workspaceId, _targetWorkspaceId);
    },
  );

  testWidgets('share sheet and successful feedback follow locale changes', (
    tester,
  ) async {
    final todos = await _hydratedTodos([_todo('locale-task', 'Locale task')]);
    final share = _FixtureShareProvider(
      workspaces: [_workspace(_targetWorkspaceId, 'Team space')],
    );
    await tester.runAsync(loadWeeklyReviewScreenshotFonts);
    final fixture = _TodoFixture(
      todos: todos,
      auth: _auth(),
      share: share,
      textScale: 1.6,
    );
    await fixture.mount(tester, size: const Size(320, 844));
    _registerCleanup(tester, fixture);

    await _openShareSheet(tester);
    final revision = todos.revision;
    final original = todos.todos.single.toJson();
    final sheetElement = tester.element(find.byType(AppModalSheet));
    for (final locale in [AppLocale.zh, AppLocale.en, AppLocale.zh]) {
      I18n.setLocale(locale);
      await tester.pumpAndSettle();
      expect(tester.element(find.byType(AppModalSheet)), same(sheetElement));
      expect(todos.revision, revision);
      expect(todos.todos.single.toJson(), original);
      expect(todos.updates, isEmpty);
      expect(share.loadCount, 0);
      expect(find.text('Team space'), findsOneWidget);
      expect(find.text(TodoBoardUiCopy.onlyMyselfVisible), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _captureScreenshot(
        tester,
        fixture.screenshotKey,
        'sharing-sheet-${locale.name}.png',
      );
    }
    I18n.setLocale(AppLocale.en);
    await tester.pumpAndSettle();
    expect(find.text(TodoBoardUiCopy.shareListDialogTitle), findsOneWidget);
    expect(find.text('Assign "$_groupName" to a shared space'), findsOneWidget);
    expect(tester.element(find.byType(AppModalSheet)), same(sheetElement));

    await tester.tap(_workspaceTileFinder(tester, 'Team space'));
    await tester.pumpAndSettle();
    expect(todos.updates, hasLength(1));
    expect(find.text(TodoBoardUiCopy.shareStatusUpdated), findsOneWidget);

    I18n.setLocale(AppLocale.zh);
    await tester.pumpAndSettle();
    expect(find.text(TodoBoardUiCopy.shareStatusUpdated), findsOneWidget);
  });

  testWidgets(
    'selecting the already assigned workspace does not show success',
    (tester) async {
      final todos = await _hydratedTodos([
        _todo('no-op-task', 'No-op task', workspaceId: _sourceWorkspaceId),
      ]);
      final share = _FixtureShareProvider(
        workspaces: [_workspace(_sourceWorkspaceId, 'Current space')],
      );
      final fixture = _TodoFixture(todos: todos, auth: _auth(), share: share);
      await fixture.mount(tester);
      _registerCleanup(tester, fixture);

      await _openShareSheet(tester);
      await tester.tap(_workspaceTileFinder(tester, 'Current space'));
      await tester.pumpAndSettle();

      expect(todos.updates, hasLength(1));
      expect(todos.updates.single.workspaceId, _sourceWorkspaceId);
      expect(todos.todos.single.workspaceId, _sourceWorkspaceId);
      expect(find.text(TodoBoardUiCopy.shareStatusUpdated), findsNothing);
    },
  );
}

TodoItem _todo(String id, String title, {String workspaceId = 'private'}) {
  return TodoItem(
    id: id,
    title: title,
    workspaceId: workspaceId,
    listGroupName: _groupName,
    date: DateTime(2026, 10, 15),
  );
}

Workspace _workspace(
  String id,
  String name, {
  WorkspaceRole role = WorkspaceRole.editor,
}) {
  final now = DateTime.utc(2026, 10, 15);
  return Workspace(
    id: id,
    name: name,
    ownerUserId: 'workspace-owner',
    isPrivate: false,
    createdAt: now,
    updatedAt: now,
    members: [
      WorkspaceMember(
        workspaceId: id,
        userId: _userId,
        username: 'Share user',
        role: role,
        joinedAt: now,
      ),
    ],
  );
}

AuthProvider _auth() => AuthProvider(
  initialState: const AuthState(userId: _userId, token: 'fixture-token'),
);

Future<_RecordingTodoProvider> _hydratedTodos(
  Iterable<TodoItem> initialItems,
) async {
  final items = initialItems.toList();
  SharedPreferences.setMockInitialValues({
    'todos': jsonEncode(items.map((item) => item.toJson()).toList()),
  });
  final provider = _RecordingTodoProvider();
  await provider.loadFromStorage();
  expect(provider.isStorageHydrated, isTrue);
  return provider;
}

Finder _shareButtonFinder(WidgetTester tester) {
  final finder = find.byWidgetPredicate(
    (widget) =>
        widget is IconButton &&
        widget.tooltip == TodoBoardUiCopy.shareListTooltip,
  );
  expect(finder, findsOneWidget);
  return finder;
}

VoidCallback _captureShareOpener(WidgetTester tester) =>
    tester.widget<IconButton>(_shareButtonFinder(tester)).onPressed!;

Future<void> _openShareSheet(WidgetTester tester) async {
  await tester.tap(_shareButtonFinder(tester));
  await tester.pumpAndSettle();
  expect(find.text(TodoBoardUiCopy.shareListDialogTitle), findsOneWidget);
}

Finder _workspaceTileFinder(WidgetTester tester, String name) {
  return find.byWidgetPredicate(
    (widget) =>
        widget is ListTile &&
        widget.title is Text &&
        (widget.title! as Text).data == name,
  );
}

ListTile _workspaceTile(WidgetTester tester, String name) {
  final finder = _workspaceTileFinder(tester, name);
  expect(finder, findsOneWidget);
  return tester.widget<ListTile>(finder);
}

VoidCallback _workspaceTileAction(WidgetTester tester, String name) =>
    _workspaceTile(tester, name).onTap!;

void _registerCleanup(WidgetTester tester, _TodoFixture fixture) {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
    tester.view.reset();
  });
}

class _TodoFixture {
  _TodoFixture({
    required _RecordingTodoProvider todos,
    required AuthProvider auth,
    required _FixtureShareProvider share,
    this.textScale = 1.0,
    this.lock,
  }) : _todos = todos,
       _auth = auth,
       _share = share,
       _notifiers = {todos, auth, share, ?lock};

  final GlobalKey<_TodoHarnessState> harnessKey =
      GlobalKey<_TodoHarnessState>();
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  final AppAccessRouteGate routeGate = AppAccessRouteGate();
  final GlobalKey screenshotKey = GlobalKey();
  final double textScale;
  final AppLockProvider? lock;
  _RecordingTodoProvider _todos;
  AuthProvider _auth;
  _FixtureShareProvider _share;
  final Set<ChangeNotifier> _notifiers;

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(390, 1200),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      _TodoHarness(
        key: harnessKey,
        todos: _todos,
        auth: _auth,
        share: _share,
        navigatorKey: navigatorKey,
        routeGate: routeGate,
        screenshotKey: screenshotKey,
        textScale: textScale,
        lock: lock,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(TodoBoardUiCopy.viewList));
    await tester.pumpAndSettle();
    expect(find.text(_groupName), findsOneWidget);
  }

  void replaceProviders({
    required _RecordingTodoProvider todos,
    required AuthProvider auth,
    required _FixtureShareProvider share,
  }) {
    _notifiers
      ..add(todos)
      ..add(auth)
      ..add(share);
    _todos = todos;
    _auth = auth;
    _share = share;
    harnessKey.currentState!.replaceProviders(
      todos: todos,
      auth: auth,
      share: share,
    );
  }

  void dispose() {
    routeGate.dispose();
    for (final notifier in _notifiers) {
      notifier.dispose();
    }
  }
}

class _TodoHarness extends StatefulWidget {
  const _TodoHarness({
    super.key,
    required this.todos,
    required this.auth,
    required this.share,
    required this.navigatorKey,
    required this.routeGate,
    required this.screenshotKey,
    required this.textScale,
    this.lock,
  });

  final _RecordingTodoProvider todos;
  final AuthProvider auth;
  final _FixtureShareProvider share;
  final GlobalKey<NavigatorState> navigatorKey;
  final AppAccessRouteGate routeGate;
  final GlobalKey screenshotKey;
  final double textScale;
  final AppLockProvider? lock;

  @override
  State<_TodoHarness> createState() => _TodoHarnessState();
}

class _TodoHarnessState extends State<_TodoHarness> {
  late _RecordingTodoProvider _todos = widget.todos;
  late AuthProvider _auth = widget.auth;
  late _FixtureShareProvider _share = widget.share;

  void replaceProviders({
    required _RecordingTodoProvider todos,
    required AuthProvider auth,
    required _FixtureShareProvider share,
  }) {
    setState(() {
      _todos = todos;
      _auth = auth;
      _share = share;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<TodoProvider>.value(value: _todos),
        ChangeNotifierProvider<AuthProvider>.value(value: _auth),
        ChangeNotifierProvider<ShareProvider>.value(value: _share),
        if (widget.lock != null)
          ChangeNotifierProvider<AppLockProvider>.value(value: widget.lock!),
        ChangeNotifierProvider(create: (_) => HabitProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AiService()),
        ChangeNotifierProvider(create: (_) => GoalProvider()),
      ],
      child: MaterialApp(
        theme: AppBrands.defaultBrand.theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(widget.textScale)),
          child: RepaintBoundary(key: widget.screenshotKey, child: child!),
        ),
        navigatorKey: widget.navigatorKey,
        navigatorObservers: [widget.routeGate],
        home: const TodoScreen(),
      ),
    );
  }
}

class _FixtureShareProvider extends ShareProvider {
  _FixtureShareProvider({
    Iterable<Workspace> workspaces = const [],
    this.loadGate,
    this.workspacesAfterLoad,
  }) : _workspaces = List.of(workspaces) {
    userIdGetter = () => _userId;
  }

  List<Workspace> _workspaces;
  final Completer<void>? loadGate;
  final List<Workspace>? workspacesAfterLoad;
  int loadCount = 0;

  @override
  List<Workspace> get workspaces => List.unmodifiable(_workspaces);

  @override
  WorkspaceRole roleFor(String? workspaceId) {
    if (workspaceId == null ||
        workspaceId.isEmpty ||
        workspaceId == 'private') {
      return WorkspaceRole.owner;
    }
    for (final workspace in _workspaces) {
      if (workspace.id == workspaceId) return workspace.roleFor(_userId);
    }
    return WorkspaceRole.viewer;
  }

  @override
  Future<void> load({bool force = false, bool notifyLoading = true}) async {
    loadCount++;
    await loadGate?.future;
    if (workspacesAfterLoad != null) {
      _workspaces = List.of(workspacesAfterLoad!);
      notifyListeners();
    }
  }

  void setWorkspaces(Iterable<Workspace> workspaces) {
    _workspaces = List.of(workspaces);
    notifyListeners();
  }
}

class _ListGroupWorkspaceUpdate {
  const _ListGroupWorkspaceUpdate({
    required this.groupName,
    required this.workspaceId,
    required this.userId,
    required this.expectedAccountDataGeneration,
    required this.canWrite,
    required this.expectedGroupMembers,
  });

  final String groupName;
  final String workspaceId;
  final String? userId;
  final int? expectedAccountDataGeneration;
  final bool Function()? canWrite;
  final Map<String, TodoItem>? expectedGroupMembers;
}

class _RecordingTodoProvider extends TodoProvider {
  final List<_ListGroupWorkspaceUpdate> updates = [];

  @override
  Future<bool> updateListGroupWorkspace(
    String groupName,
    String workspaceId, {
    String? userId,
    int? expectedAccountDataGeneration,
    bool Function()? canWrite,
    Map<String, TodoItem>? expectedGroupMembers,
  }) {
    updates.add(
      _ListGroupWorkspaceUpdate(
        groupName: groupName,
        workspaceId: workspaceId,
        userId: userId,
        expectedAccountDataGeneration: expectedAccountDataGeneration,
        canWrite: canWrite,
        expectedGroupMembers: expectedGroupMembers,
      ),
    );
    return super.updateListGroupWorkspace(
      groupName,
      workspaceId,
      userId: userId,
      expectedAccountDataGeneration: expectedAccountDataGeneration,
      canWrite: canWrite,
      expectedGroupMembers: expectedGroupMembers,
    );
  }
}

Future<void> _captureScreenshot(
  WidgetTester tester,
  GlobalKey key,
  String name,
) async {
  final directory = Platform.environment['DUOYI_TODO_SHARE_SCREENSHOT_DIR'];
  if (directory == null) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File('$directory/$name').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

class _RotatingAuth extends AuthProvider {
  _RotatingAuth()
    : super(
        initialState: const AuthState(userId: _userId, token: 'fixture-token'),
      );
  int _rotation = 0;
  @override
  int get sessionGeneration => super.sessionGeneration + _rotation;
  void rotateSession() {
    _rotation++;
    notifyListeners();
  }
}
