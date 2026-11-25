// Real mounted focus-room controls with synthetic delayed provider results.
import 'dart:async';

import 'package:duoyi/core/focus_room_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/focus_room.dart';
import 'package:duoyi/models/pomodoro.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/custom_focus_sound_provider.dart';
import 'package:duoyi/providers/focus_room_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/pomodoro_screen.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/services/focus_dnd_service.dart';
import 'package:duoyi/services/focus_room_api.dart';
import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/weekly_review_screenshot_font.dart';

const _actions = [
  'invite-sheet',
  'friend-sheet',
  'create',
  'revoke',
  'join',
  'add',
  'accept',
  'reject',
  'cancel',
  'remove',
];
const _friend = FocusFriend(
  userId: 'synthetic-friend',
  username: 'Synthetic peer',
  status: 'accepted',
  online: false,
);
const _incoming = FocusFriendRequest(
  id: 'synthetic-incoming',
  userId: 'synthetic-incoming-peer',
  username: 'Synthetic incoming',
  direction: 'incoming',
  status: 'pending',
  online: false,
);
const _outgoing = FocusFriendRequest(
  id: 'synthetic-outgoing',
  userId: 'synthetic-outgoing-peer',
  username: 'Synthetic outgoing',
  direction: 'outgoing',
  status: 'pending',
  online: false,
);

class _Rooms extends FocusRoomProvider {
  _Rooms(this.action);
  final String action;
  bool armed = false;
  final entered = Completer<void>();
  final released = Completer<void>();
  int heldCalls = 0;
  int clipboardWrites = 0;

  FocusRoomInvite get invite => FocusRoomInvite(
    id: 'synthetic-invite',
    code: 'SYNTHETIC',
    room: rooms.first,
  );

  Future<void> hold(String operation) async {
    if (!armed || operation != action) return;
    heldCalls++;
    if (!entered.isCompleted) entered.complete();
    await released.future;
  }

  @override
  List<FocusFriend> get focusFriends => const [_friend];
  @override
  List<FocusFriendRequest> get incomingFriendRequests => const [_incoming];
  @override
  List<FocusFriendRequest> get outgoingFriendRequests => const [_outgoing];
  @override
  List<FocusRoomInvite> invitesForRoom(String roomId) => [invite];
  @override
  void watchRealtimeRankings({int intervalSeconds = 15}) {}
  @override
  Future<void> loadGlobalRanking({bool force = false}) async {}
  @override
  Future<void> loadFocusFriendsAndRanking({bool force = false}) =>
      hold('friend-sheet');
  @override
  Future<void> syncRemoteRankings(
    Iterable<PomodoroSession> sessions, {
    String displayName = '我',
    bool active = true,
    bool force = false,
  }) async {}
  @override
  Future<List<FocusRoomInvite>> loadInvitesForRoom(String roomId) async {
    await hold('invite-sheet');
    return [invite];
  }

  @override
  Future<FocusRoomInvite> createInviteForRoom(
    String roomId, {
    DateTime? expiresAt,
    int? maxUses,
  }) async {
    await hold('create');
    return invite;
  }

  @override
  Future<void> revokeInviteForRoom(String roomId, String inviteId) =>
      hold('revoke');
  @override
  Future<FocusRoom> acceptInviteCode(
    String code, {
    String displayName = '我',
  }) async {
    await hold('join');
    return rooms.first;
  }

  @override
  Future<FocusFriend> addFocusFriend(String username) async {
    await hold('add');
    return _friend;
  }

  @override
  Future<FocusFriend> acceptFocusFriendRequest(String requesterUserId) async {
    await hold('accept');
    return _friend;
  }

  @override
  Future<void> rejectFocusFriendRequest(String requesterUserId) =>
      hold('reject');
  @override
  Future<void> cancelFocusFriendRequest(String friendUserId) => hold('cancel');
  @override
  Future<void> removeFocusFriend(String friendUserId) => hold('remove');
}

class _Timer extends PomodoroProvider {
  int roomWrites = 0;
  @override
  PomodoroState get state => const PomodoroState(
    remainingSeconds: 1500,
    totalSeconds: 1500,
    isRunning: false,
    type: PomodoroType.focus,
    completedSessions: 0,
    focusRoomId: FocusRoomProvider.defaultRoomId,
  );
  @override
  Future<FocusDndStatus> refreshFocusDndStatus() async => focusDndStatus;
  @override
  Future<void> setFocusRoomId(String? id) async {
    roomWrites++;
  }
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      350,
      scrollable: find
          .descendant(
            of: find.byKey(
              const PageStorageKey<String>('focus_room_tab_scroll'),
            ),
            matching: find.byType(Scrollable),
          )
          .first,
    );
  }
  expect(target, findsOneWidget);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _begin(WidgetTester tester, _Rooms rooms, AppLocale locale) async {
  final action = rooms.action;
  if (action == 'invite-sheet' || action == 'create' || action == 'revoke') {
    rooms.armed = action == 'invite-sheet';
    await _tap(
      tester,
      find.byTooltip(FocusRoomUiCopy.manageInvitesTooltip(locale)),
    );
    if (action == 'invite-sheet') return;
    if (action == 'create') {
      await _tap(
        tester,
        find.text(FocusRoomUiCopy.newInviteCodeButton(locale)),
      );
      rooms.armed = true;
      await _tap(
        tester,
        find.text(FocusRoomUiCopy.createAndCopyButton(locale)),
      );
    } else {
      rooms.armed = true;
      await _tap(
        tester,
        find.byTooltip(FocusRoomUiCopy.revokeInviteTooltip(locale)),
      );
    }
    return;
  }
  if (action == 'join') {
    await _tap(
      tester,
      find.text(FocusRoomUiCopy.enterInviteCodeAction(locale)),
    );
    await tester.enterText(find.byType(TextField), 'SYNTHETIC');
    rooms.armed = true;
    await _tap(tester, find.text(FocusRoomUiCopy.joinStudyRoomAction(locale)));
    return;
  }
  rooms.armed = action == 'friend-sheet';
  await _tap(
    tester,
    find.byTooltip(FocusRoomUiCopy.manageFriendsTooltip(locale)),
  );
  if (action == 'friend-sheet') return;
  if (action == 'add') {
    await _tap(
      tester,
      find.text(FocusRoomUiCopy.sendFriendRequestButton(locale)),
    );
    await tester.enterText(find.byType(TextField), 'synthetic-peer');
    rooms.armed = true;
    await _tap(tester, find.text(FocusRoomUiCopy.sendRequestAction(locale)));
  } else {
    final tooltip = switch (action) {
      'accept' => FocusRoomUiCopy.acceptFriendRequestTooltip(locale),
      'reject' => FocusRoomUiCopy.rejectFriendRequestTooltip(locale),
      'cancel' => FocusRoomUiCopy.cancelFriendRequestTooltip(locale),
      _ => FocusRoomUiCopy.removeFriendTooltip(locale),
    };
    rooms.armed = true;
    await _tap(tester, find.byTooltip(tooltip));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadWeeklyReviewScreenshotFonts);
  final originalLocale = I18n.current;
  tearDown(() => I18n.setLocale(originalLocale));
  for (final brand in ['defaultBrand', 'liquidGlass']) {
    for (final locale in AppLocale.values) {
      for (final action in _actions) {
        for (final stale in [false, true]) {
          for (final failed in [false, true]) {
            // This provider method absorbs read errors in production.
            if (action == 'friend-sheet' && failed) continue;
            testWidgets(
              '$brand/${locale.name} $action stale=$stale failure=$failed',
              (tester) async {
                SharedPreferences.setMockInitialValues({'active_brand': brand});
                tester.view.physicalSize = const Size(430, 1000);
                tester.view.devicePixelRatio = 1;
                addTearDown(tester.view.reset);
                I18n.setLocale(locale);
                final rooms = _Rooms(action);
                final timer = _Timer();
                final theme = ThemeProvider();
                final sounds = CustomFocusSoundProvider();
                final auth = AuthProvider();
                await tester.runAsync(theme.loadFromStorage);
                tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
                  SystemChannels.platform,
                  (call) async {
                    if (call.method == 'Clipboard.setData') {
                      rooms.clipboardWrites++;
                    }
                    return null;
                  },
                );
                addTearDown(() async {
                  if (!rooms.released.isCompleted) rooms.released.complete();
                  await tester.pumpWidget(const SizedBox.shrink());
                  await tester.pumpAndSettle();
                  tester.binding.defaultBinaryMessenger
                      .setMockMethodCallHandler(SystemChannels.platform, null);
                  rooms.dispose();
                  timer.dispose();
                  theme.dispose();
                  sounds.dispose();
                  auth.dispose();
                });
                await tester.pumpWidget(
                  MultiProvider(
                    providers: [
                      ChangeNotifierProvider<FocusRoomProvider>.value(
                        value: rooms,
                      ),
                      ChangeNotifierProvider<PomodoroProvider>.value(
                        value: timer,
                      ),
                      ChangeNotifierProvider<ThemeProvider>.value(value: theme),
                      ChangeNotifierProvider<CustomFocusSoundProvider>.value(
                        value: sounds,
                      ),
                      ChangeNotifierProvider<AuthProvider>.value(value: auth),
                    ],
                    child: MaterialApp(
                      theme: theme.brand.theme,
                      home: const PomodoroScreen(),
                    ),
                  ),
                );
                await tester.pumpAndSettle();
                expect(theme.brand.id, brand);
                tester
                    .widget<TabBar>(find.byType(TabBar))
                    .controller!
                    .animateTo(2);
                await tester.pumpAndSettle();
                await _begin(tester, rooms, locale);
                expect(
                  rooms.entered.isCompleted,
                  isTrue,
                  reason:
                      'The actual rendered action must reach its held operation',
                );
                expect(rooms.heldCalls, 1);
                final dialogsBefore = find.byType(AppDialog).evaluate().length;
                if (stale) {
                  AccountLocalDataCleaner.invalidateInFlightAccountWrites();
                  rooms.resetLocalState();
                  await tester.pump();
                }
                if (failed) {
                  rooms.released.completeError(
                    const ApiException('synthetic delayed focus error'),
                  );
                } else {
                  rooms.released.complete();
                }
                await tester.pumpAndSettle();
                expect(find.byType(PomodoroScreen), findsOneWidget);
                if (action.endsWith('-sheet')) {
                  final title = action == 'invite-sheet'
                      ? FocusRoomUiCopy.inviteManagementTitle(locale)
                      : FocusRoomUiCopy.focusFriendsTitle(locale);
                  expect(
                    find.text(title),
                    !stale && !failed ? findsOneWidget : findsNothing,
                  );
                  expect(
                    find.byType(SnackBar),
                    !stale && failed ? findsOneWidget : findsNothing,
                  );
                } else {
                  expect(
                    find.byType(SnackBar),
                    stale ? findsNothing : findsOneWidget,
                  );
                  if (stale) {
                    expect(
                      find.byType(AppDialog),
                      findsNWidgets(dialogsBefore),
                    );
                  }
                  expect(
                    timer.roomWrites,
                    !stale && !failed && action == 'join' ? 1 : 0,
                  );
                  expect(
                    rooms.clipboardWrites,
                    !stale && !failed && action == 'create' ? 1 : 0,
                  );
                }
                expect(tester.takeException(), isNull);
              },
            );
          }
        }
      }
    }
  }
}
