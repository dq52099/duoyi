import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/focus_room.dart';
import 'package:duoyi/models/pomodoro.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/custom_focus_sound_provider.dart';
import 'package:duoyi/providers/focus_room_provider.dart';
import 'package:duoyi/providers/pomodoro_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/pomodoro_screen.dart';
import 'package:duoyi/services/focus_dnd_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _week = DateTime(2026, 10, 5);
const _literal = '单次专注超过 4 小时已封顶';

List<FocusRoomRankingEntry> _entries() => [
  FocusRoomRankingEntry(
    id: 'local',
    name: 'Local generated',
    weeklySeconds: 3600,
    sessionCount: 1,
    isCurrentUser: true,
    rank: 1,
    flagged: true,
    generatedFlagReasons:
        FocusFlagReasonCode.longSessionCap.mask |
        FocusFlagReasonCode.futureSessionIgnored.mask,
  ),
  const FocusRoomRankingEntry(
    id: 'remote',
    name: 'Literal remote',
    weeklySeconds: 1800,
    sessionCount: 1,
    isCurrentUser: false,
    rank: 2,
    flagged: true,
    flagReason: _literal,
  ),
];

class _CachedRooms extends FocusRoomProvider {
  _CachedRooms() {
    room = FocusRoom(
      id: 'cached-room',
      name: 'Literal room',
      description: 'Fixture',
      weeklyTargetSeconds: 7200,
      accentColor: Colors.blue.toARGB32(),
      members: const [],
      createdAt: _week,
    );
    final entries = _entries();
    joined = FocusRoomRanking(
      room: room,
      entries: entries,
      userWeeklySeconds: 3600,
      userSessionCount: 1,
      weekStart: _week,
      weekEnd: _week.add(const Duration(days: 7)),
    );
    social = [
      for (final scope in FocusLeaderboardScope.values)
        FocusSocialRanking(
          scope: scope,
          entries: entries,
          weekStart: _week,
          weekEnd: _week.add(const Duration(days: 7)),
          suspiciousEntryCount: 2,
        ),
    ];
  }
  late final FocusRoom room;
  late final FocusRoomRanking joined;
  late final List<FocusSocialRanking> social;
  int refreshCalls = 0;
  @override
  String? get activeRoomId => null;
  @override
  List<FocusRoom> get rooms => [room];
  @override
  List<FocusRoom> get joinedRooms => [room];
  @override
  Set<String> get joinedRoomIds => {room.id};
  @override
  FocusRoomRanking effectiveRankingFor(
    String roomId,
    Iterable<PomodoroSession> sessions, {
    DateTime? now,
    String currentUserName = '我',
  }) => joined;
  @override
  FocusSocialRanking socialRankingFor(
    FocusLeaderboardScope scope,
    Iterable<PomodoroSession> sessions, {
    DateTime? now,
    String currentUserName = '我',
  }) => social.singleWhere((r) => r.scope == scope);
  @override
  void watchRealtimeRankings({int intervalSeconds = 15}) => refreshCalls++;
  @override
  Future<void> loadFocusFriendsAndRanking({bool force = false}) async {
    refreshCalls++;
  }

  @override
  Future<void> loadGlobalRanking({bool force = false}) async {
    refreshCalls++;
  }

  @override
  Future<void> syncRemoteRankings(
    Iterable<PomodoroSession> sessions, {
    String displayName = '我',
    bool active = true,
    bool force = false,
  }) async {
    refreshCalls++;
  }
}

class _IdlePomodoro extends PomodoroProvider {
  @override
  Future<FocusDndStatus> refreshFocusDndStatus() async =>
      const FocusDndStatus.unavailable();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    I18n.setLocale(AppLocale.zh);
  });
  tearDown(() => I18n.setLocale(AppLocale.zh));

  testWidgets(
    'both cached ranking selectors repaint while retaining scores and literal reasons',
    (tester) async {
      tester.view.physicalSize = const Size(800, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final rooms = _CachedRooms();
      final pomodoro = _IdlePomodoro();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        rooms.dispose();
        pomodoro.dispose();
      });
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<FocusRoomProvider>.value(value: rooms),
            ChangeNotifierProvider<PomodoroProvider>.value(value: pomodoro),
            ChangeNotifierProvider(create: (_) => ThemeProvider()),
            ChangeNotifierProvider(create: (_) => CustomFocusSoundProvider()),
            ChangeNotifierProvider(create: (_) => AuthProvider()),
          ],
          child: const MaterialApp(home: PomodoroScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .descendant(of: find.byType(TabBar), matching: find.byType(Tab))
            .at(2),
      );
      await tester.pumpAndSettle();
      final refreshCalls = rooms.refreshCalls;
      final entries = rooms.joined.entries;
      final scores = entries
          .map((e) => [e.id, e.rank, e.weeklySeconds])
          .toList();
      final joinedCards = find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_FocusRoomRankingCard',
      );
      final socialCards = find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_FocusSocialRankingCard',
      );
      expect(joinedCards, findsOneWidget);
      expect(socialCards, findsNWidgets(2));
      expect(find.text('好友专注榜'), findsOneWidget);
      expect(find.text('全局专注榜'), findsOneWidget);

      List<String> reasons(Finder card) => tester
          .widgetList<Tooltip>(
            find.descendant(of: card, matching: find.byType(Tooltip)),
          )
          .map((t) => t.message ?? '')
          .toList();

      for (final locale in [AppLocale.en, AppLocale.zh]) {
        I18n.setLocale(locale);
        await tester.pumpAndSettle();
        final generated = entries.first.flagReasonFor(locale)!;
        expect(reasons(joinedCards), contains(generated));
        expect(reasons(joinedCards), contains(_literal));
        for (var i = 0; i < 2; i++) {
          expect(reasons(socialCards.at(i)), contains(generated));
          expect(reasons(socialCards.at(i)), contains(_literal));
        }
        expect(
          find.text(locale == AppLocale.en ? 'Friends focus ranking' : '好友专注榜'),
          findsOneWidget,
        );
        expect(
          find.text(locale == AppLocale.en ? 'Global focus ranking' : '全局专注榜'),
          findsOneWidget,
        );
        expect(
          find.text(
            locale == AppLocale.en
                ? 'Ranked by friends’ credited focus time this week'
                : '按好友本周有效专注时长排名',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            locale == AppLocale.en
                ? 'Ranked by credited focus time across all users this week'
                : '按全站本周有效专注时长排名',
          ),
          findsOneWidget,
        );
        expect(rooms.joined.entries, same(entries));
        expect(
          entries.map((e) => [e.id, e.rank, e.weeklySeconds]).toList(),
          scores,
        );
        expect(rooms.refreshCalls, refreshCalls);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      I18n.setLocale(AppLocale.en);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
