import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/focus_room.dart';
import '../models/pomodoro.dart';
import '../services/api_client.dart';
import '../services/focus_room_api.dart';

class FocusRoomProvider extends ChangeNotifier {
  static const storageKey = 'duoyi_focus_rooms';
  static const defaultRoomId = 'deep_work_room';
  static const _remoteRefreshInterval = Duration(minutes: 2);
  static const _friendRefreshInterval = Duration(minutes: 2);
  static const _globalRefreshInterval = Duration(minutes: 2);
  static const _realtimeRetryBackoff = [
    Duration(seconds: 10),
    Duration(seconds: 30),
    Duration(seconds: 60),
  ];

  List<FocusRoom> _rooms = _defaultRooms;
  final Set<String> _joinedRoomIds = {defaultRoomId};
  final Map<String, FocusRoomRanking> _remoteRankings = {};
  final Map<String, StreamSubscription<FocusRoomRemoteRanking>>
  _rankingEventSubscriptions = {};
  StreamSubscription<FocusRoomRemoteRanking>? _globalRankingEventSubscription;
  final Map<String, List<FocusRoomInvite>> _inviteCache = {};
  List<FocusFriend> _focusFriends = const <FocusFriend>[];
  List<FocusFriendRequest> _incomingFriendRequests =
      const <FocusFriendRequest>[];
  List<FocusFriendRequest> _outgoingFriendRequests =
      const <FocusFriendRequest>[];
  FocusSocialRanking? _remoteFriendRanking;
  FocusSocialRanking? _remoteGlobalRanking;
  String? _activeRoomId = defaultRoomId;
  bool _remoteLoading = false;
  bool _friendLoading = false;
  bool _globalLoading = false;
  String? _lastRemoteError;
  DateTime? _lastRemoteSyncAt;
  DateTime? _lastFriendSyncAt;
  DateTime? _lastGlobalSyncAt;
  String? _realtimeClientKey;
  DateTime? _realtimeRetryAfter;
  Timer? _realtimeNotifyDebounce;
  bool _fallbackToLocal = false;
  int _realtimeFailureCount = 0;

  ApiClient? Function()? apiClientGetter;
  VoidCallback? onLocalChanged;

  List<FocusRoom> get rooms => List.unmodifiable(_rooms);
  Set<String> get joinedRoomIds => Set.unmodifiable(_joinedRoomIds);
  String? get activeRoomId => _activeRoomId;
  FocusRoom? get activeRoom => roomById(_activeRoomId);
  bool get remoteLoading => _remoteLoading;
  bool get friendLoading => _friendLoading;
  bool get globalLoading => _globalLoading;
  String? get lastRemoteError => _lastRemoteError;
  DateTime? get lastRemoteSyncAt => _lastRemoteSyncAt;
  DateTime? get lastFriendSyncAt => _lastFriendSyncAt;
  DateTime? get lastGlobalSyncAt => _lastGlobalSyncAt;
  bool get fallbackToLocal => _fallbackToLocal;
  bool get realtimeRankingsActive =>
      _rankingEventSubscriptions.isNotEmpty ||
      _globalRankingEventSubscription != null;
  bool get remoteFriendRankingActive => _remoteFriendRanking != null;
  bool get remoteGlobalRankingActive => _remoteGlobalRanking != null;
  List<FocusFriend> get focusFriends => List.unmodifiable(_focusFriends);
  List<FocusFriendRequest> get incomingFriendRequests =>
      List.unmodifiable(_incomingFriendRequests);
  List<FocusFriendRequest> get outgoingFriendRequests =>
      List.unmodifiable(_outgoingFriendRequests);
  List<FocusRoom> get joinedRooms =>
      _rooms.where((room) => _joinedRoomIds.contains(room.id)).toList();
  List<FocusRoomInvite> invitesForRoom(String roomId) =>
      List.unmodifiable(_inviteCache[roomId] ?? const <FocusRoomInvite>[]);

  String _focusRoomRemoteError(
    Object error, {
    required String fallbackMessage,
  }) {
    final message = error is ApiException ? error.message : error.toString();
    if (isFocusRoomRealtimeTransportError(error)) {
      return focusRoomRankingUnavailableMessage;
    }
    if (isBackendCompatibilityDiagnosticMessage(message)) return message;
    return userVisibleApiError(error, fallbackMessage: fallbackMessage);
  }

  void _debugLogRemoteError(
    String label,
    Object error, {
    StackTrace? stackTrace,
    ApiClient? client,
  }) {
    if (!kDebugMode) return;
    debugPrint(
      '[FocusRoomProvider] $label: '
      '${sanitizeFocusRoomRealtimeDiagnostic(error, token: client?.token)}',
    );
    if (stackTrace != null) {
      debugPrint(
        sanitizeFocusRoomRealtimeDiagnostic(stackTrace, token: client?.token),
      );
    }
  }

  void _markRemoteRankingSuccess({bool realtime = false}) {
    if (!realtime && _realtimeRetryAfter != null && _realtimeFailureCount > 0) {
      return;
    }
    _fallbackToLocal = false;
    _realtimeFailureCount = 0;
    _realtimeRetryAfter = null;
    if (_lastRemoteError == focusRoomRankingUnavailableMessage) {
      _lastRemoteError = null;
    }
  }

  void _markRemoteRankingFailure(
    Object error, {
    required String fallbackMessage,
  }) {
    _fallbackToLocal = true;
    _lastRemoteError = _focusRoomRemoteError(
      error,
      fallbackMessage: fallbackMessage,
    );
  }

  bool _markRealtimeRankingFailure(
    Object error, {
    required ApiClient client,
    StackTrace? stackTrace,
    required String label,
  }) {
    _debugLogRemoteError(label, error, stackTrace: stackTrace, client: client);
    final retryDelay = _nextRealtimeRetryDelay();
    final retryAfter = DateTime.now().add(retryDelay);
    final changed =
        !_fallbackToLocal ||
        _lastRemoteError != focusRoomRankingUnavailableMessage ||
        _realtimeRetryAfter != retryAfter;
    _fallbackToLocal = true;
    _lastRemoteError = focusRoomRankingUnavailableMessage;
    _realtimeRetryAfter = retryAfter;
    return changed;
  }

  Duration _nextRealtimeRetryDelay() {
    final index = _realtimeFailureCount < _realtimeRetryBackoff.length
        ? _realtimeFailureCount
        : _realtimeRetryBackoff.length - 1;
    _realtimeFailureCount += 1;
    return _realtimeRetryBackoff[index];
  }

  static const List<FocusRoomMemberSeed> _friendLeaderboardSeeds = [
    FocusRoomMemberSeed(
      id: 'friend-lin',
      name: '林同学',
      weeklySeconds: 9 * 60 * 60 + 15 * 60,
      sessionCount: 18,
    ),
    FocusRoomMemberSeed(
      id: 'friend-chen',
      name: '陈计划',
      weeklySeconds: 6 * 60 * 60 + 35 * 60,
      sessionCount: 13,
    ),
    FocusRoomMemberSeed(
      id: 'friend-ye',
      name: '叶书签',
      weeklySeconds: 4 * 60 * 60 + 50 * 60,
      sessionCount: 9,
    ),
  ];

  static const List<FocusRoomMemberSeed> _globalLeaderboardSeeds = [
    FocusRoomMemberSeed(
      id: 'global-001',
      name: '全站第一',
      weeklySeconds: 32 * 60 * 60 + 20 * 60,
      sessionCount: 52,
    ),
    FocusRoomMemberSeed(
      id: 'global-002',
      name: '晨间学习者',
      weeklySeconds: 24 * 60 * 60 + 45 * 60,
      sessionCount: 41,
    ),
    FocusRoomMemberSeed(
      id: 'global-003',
      name: '深度工作者',
      weeklySeconds: 18 * 60 * 60 + 10 * 60,
      sessionCount: 27,
    ),
    FocusRoomMemberSeed(
      id: 'global-suspicious',
      name: '异常记录',
      weeklySeconds: 91 * 60 * 60,
      sessionCount: 4,
    ),
  ];

  static final List<FocusRoom> _defaultRooms = [
    FocusRoom(
      id: defaultRoomId,
      name: '深度工作自习室',
      description: '适合写作、开发和高强度脑力任务。',
      weeklyTargetSeconds: 8 * 60 * 60,
      accentColor: 0xFFE53935,
      createdAt: DateTime(2026, 1, 1),
      members: const [
        FocusRoomMemberSeed(
          id: 'lin',
          name: '林同学',
          weeklySeconds: 7 * 60 * 60 + 20 * 60,
          sessionCount: 14,
        ),
        FocusRoomMemberSeed(
          id: 'chen',
          name: '陈计划',
          weeklySeconds: 5 * 60 * 60 + 40 * 60,
          sessionCount: 11,
        ),
        FocusRoomMemberSeed(
          id: 'xu',
          name: '徐复盘',
          weeklySeconds: 3 * 60 * 60 + 55 * 60,
          sessionCount: 8,
        ),
      ],
    ),
    FocusRoom(
      id: 'exam_sprint_room',
      name: '考试冲刺自习室',
      description: '按周目标推进刷题、背诵和复习。',
      weeklyTargetSeconds: 12 * 60 * 60,
      accentColor: 0xFF7C4DFF,
      createdAt: DateTime(2026, 1, 1),
      members: const [
        FocusRoomMemberSeed(
          id: 'gao',
          name: '高冲刺',
          weeklySeconds: 10 * 60 * 60 + 10 * 60,
          sessionCount: 19,
        ),
        FocusRoomMemberSeed(
          id: 'zhou',
          name: '周错题',
          weeklySeconds: 8 * 60 * 60 + 45 * 60,
          sessionCount: 17,
        ),
        FocusRoomMemberSeed(
          id: 'li',
          name: '李晨读',
          weeklySeconds: 6 * 60 * 60 + 30 * 60,
          sessionCount: 13,
        ),
      ],
    ),
    FocusRoom(
      id: 'reading_room',
      name: '阅读自习室',
      description: '给阅读、论文和知识整理留一张安静桌子。',
      weeklyTargetSeconds: 5 * 60 * 60,
      accentColor: 0xFF00897B,
      createdAt: DateTime(2026, 1, 1),
      members: const [
        FocusRoomMemberSeed(
          id: 'ye',
          name: '叶书签',
          weeklySeconds: 4 * 60 * 60 + 50 * 60,
          sessionCount: 9,
        ),
        FocusRoomMemberSeed(
          id: 'he',
          name: '何摘录',
          weeklySeconds: 3 * 60 * 60 + 35 * 60,
          sessionCount: 7,
        ),
      ],
    ),
  ];

  Future<void> loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) {
      notifyListeners();
      return;
    }
    try {
      final decoded = json.decode(raw);
      if (decoded is! Map) return;
      final rooms = (decoded['rooms'] as List?)
          ?.whereType<Map>()
          .map((room) => FocusRoom.fromJson(Map<String, dynamic>.from(room)))
          .where((room) => room.id.isNotEmpty)
          .toList();
      if (rooms != null && rooms.isNotEmpty) {
        _rooms = _mergeDefaultRooms(rooms);
      }
      _joinedRoomIds
        ..clear()
        ..addAll(
          (decoded['joinedRoomIds'] as List? ?? const <Object>[])
              .map((id) => id.toString())
              .where((id) => roomById(id) != null),
        );
      if (_joinedRoomIds.isEmpty) _joinedRoomIds.add(defaultRoomId);
      final active = decoded['activeRoomId']?.toString();
      _activeRoomId = _joinedRoomIds.contains(active)
          ? active
          : _joinedRoomIds.first;
    } finally {
      notifyListeners();
    }
  }

  Future<void> joinRoom(String id) async {
    if (roomById(id) == null) return;
    if (_joinedRoomIds.contains(id) && _activeRoomId == id) return;
    _joinedRoomIds.add(id);
    _activeRoomId = id;
    await _save();
    onLocalChanged?.call();
    notifyListeners();
  }

  Future<void> leaveRoom(String id) async {
    if (id == defaultRoomId) return;
    _cancelRealtimeRanking(id);
    _joinedRoomIds.remove(id);
    if (_activeRoomId == id) {
      _activeRoomId = _joinedRoomIds.isEmpty ? null : _joinedRoomIds.first;
    }
    _remoteRankings.remove(id);
    await _leaveRemoteRoom(id);
    await _save();
    onLocalChanged?.call();
    notifyListeners();
  }

  Future<void> setActiveRoom(String? id) async {
    if (id != null && !_joinedRoomIds.contains(id)) return;
    if (_activeRoomId == id) return;
    _activeRoomId = id;
    await _save();
    onLocalChanged?.call();
    notifyListeners();
  }

  Future<FocusRoom> createRoom({
    required String name,
    required String description,
    required int weeklyTargetMinutes,
    int accentColor = 0xFF3949AB,
  }) async {
    final id = 'local_room_${DateTime.now().microsecondsSinceEpoch}';
    final room = FocusRoom(
      id: id,
      name: name.trim().isEmpty ? '我的自习室' : name.trim(),
      description: description.trim().isEmpty ? '自定义专注小组' : description.trim(),
      weeklyTargetSeconds: weeklyTargetMinutes.clamp(1, 10080) * 60,
      accentColor: accentColor,
      createdAt: DateTime.now(),
      members: const <FocusRoomMemberSeed>[],
    );
    _rooms = [..._rooms, room];
    _joinedRoomIds.add(id);
    _activeRoomId = id;
    await _save();
    onLocalChanged?.call();
    notifyListeners();
    return room;
  }

  Future<FocusRoomInvite> createInviteForRoom(
    String roomId, {
    DateTime? expiresAt,
    int? maxUses,
  }) async {
    final client = apiClientGetter?.call();
    final room = roomById(roomId);
    if (client == null || client.token == null || client.token!.isEmpty) {
      throw const ApiException('请先登录后再创建自习室邀请码');
    }
    if (room == null) {
      throw const ApiException('自习室不存在');
    }
    _remoteLoading = true;
    _lastRemoteError = null;
    notifyListeners();
    try {
      final invite = await FocusRoomApi(
        client,
      ).createInvite(room: room, expiresAt: expiresAt, maxUses: maxUses);
      _inviteCache[room.id] = [
        invite,
        ...(_inviteCache[room.id] ?? const <FocusRoomInvite>[]).where(
          (item) => item.id != invite.id,
        ),
      ];
      return invite;
    } catch (e) {
      _lastRemoteError = _focusRoomRemoteError(
        e,
        fallbackMessage: '自习室服务暂不可用，请稍后重试或联系管理员。',
      );
      rethrow;
    } finally {
      _remoteLoading = false;
      notifyListeners();
    }
  }

  Future<List<FocusRoomInvite>> loadInvitesForRoom(String roomId) async {
    final client = apiClientGetter?.call();
    if (client == null || client.token == null || client.token!.isEmpty) {
      throw const ApiException('请先登录后再管理自习室邀请码');
    }
    if (roomById(roomId) == null) {
      throw const ApiException('自习室不存在');
    }
    _remoteLoading = true;
    _lastRemoteError = null;
    notifyListeners();
    try {
      final invites = await FocusRoomApi(client).listInvites(roomId);
      _inviteCache[roomId] = invites;
      return invites;
    } catch (e) {
      _lastRemoteError = _focusRoomRemoteError(
        e,
        fallbackMessage: '自习室服务暂不可用，请稍后重试或联系管理员。',
      );
      rethrow;
    } finally {
      _remoteLoading = false;
      notifyListeners();
    }
  }

  Future<void> revokeInviteForRoom(String roomId, String inviteId) async {
    final client = apiClientGetter?.call();
    if (client == null || client.token == null || client.token!.isEmpty) {
      throw const ApiException('请先登录后再撤销自习室邀请码');
    }
    if (inviteId.trim().isEmpty) {
      throw const ApiException('邀请码不存在');
    }
    _remoteLoading = true;
    _lastRemoteError = null;
    notifyListeners();
    try {
      await FocusRoomApi(client).revokeInvite(inviteId);
      final existing = _inviteCache[roomId] ?? const <FocusRoomInvite>[];
      _inviteCache[roomId] = existing.map((invite) {
        if (invite.id != inviteId) return invite;
        return invite.copyWith(revoked: true);
      }).toList();
    } catch (e) {
      _lastRemoteError = _focusRoomRemoteError(
        e,
        fallbackMessage: '自习室服务暂不可用，请稍后重试或联系管理员。',
      );
      rethrow;
    } finally {
      _remoteLoading = false;
      notifyListeners();
    }
  }

  Future<FocusRoom> acceptInviteCode(
    String code, {
    String displayName = '我',
  }) async {
    final clean = code.trim();
    if (clean.isEmpty) {
      throw const ApiException('请输入自习室邀请码');
    }
    final client = apiClientGetter?.call();
    if (client == null || client.token == null || client.token!.isEmpty) {
      throw const ApiException('请先登录后再加入自习室');
    }
    _remoteLoading = true;
    _lastRemoteError = null;
    notifyListeners();
    try {
      final result = await FocusRoomApi(
        client,
      ).acceptInvite(code: clean, displayName: displayName);
      _upsertRoom(result.room);
      _joinedRoomIds.add(result.room.id);
      _activeRoomId = result.room.id;
      if (result.ranking.roomId.isNotEmpty) {
        _remoteRankings[result.room.id] = _rankingFromRemote(
          result.ranking,
          result.room,
          DateTime.now(),
        );
      }
      await _save();
      onLocalChanged?.call();
      return result.room;
    } catch (e) {
      _lastRemoteError = _focusRoomRemoteError(
        e,
        fallbackMessage: '自习室服务暂不可用，请稍后重试或联系管理员。',
      );
      rethrow;
    } finally {
      _remoteLoading = false;
      notifyListeners();
    }
  }

  FocusRoom? roomById(String? id) {
    if (id == null) return null;
    for (final room in _rooms) {
      if (room.id == id) return room;
    }
    return null;
  }

  FocusRoomRanking rankingFor(
    String roomId,
    Iterable<PomodoroSession> sessions, {
    DateTime? now,
    String currentUserName = '我',
  }) {
    final room = roomById(roomId) ?? _rooms.first;
    return buildFocusRoomRanking(
      room: room,
      sessions: sessions,
      now: now ?? DateTime.now(),
      currentUserName: currentUserName,
    );
  }

  FocusRoomRanking effectiveRankingFor(
    String roomId,
    Iterable<PomodoroSession> sessions, {
    DateTime? now,
    String currentUserName = '我',
  }) {
    if (!_fallbackToLocal) {
      final remote = _remoteRankings[roomId];
      if (remote != null) return remote;
    }
    return rankingFor(
      roomId,
      sessions,
      now: now,
      currentUserName: currentUserName,
    );
  }

  Future<void> syncRemoteRankings(
    Iterable<PomodoroSession> sessions, {
    String displayName = '我',
    bool active = true,
    bool force = false,
  }) async {
    final client = apiClientGetter?.call();
    if (client == null || client.token == null || client.token!.isEmpty) {
      _lastRemoteError = null;
      return;
    }
    final roomsToSync = joinedRooms;
    if (roomsToSync.isEmpty || _remoteLoading) return;
    final last = _lastRemoteSyncAt;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < _remoteRefreshInterval) {
      return;
    }
    _remoteLoading = true;
    _lastRemoteError = null;
    _lastRemoteSyncAt = DateTime.now();
    notifyListeners();

    try {
      final api = FocusRoomApi(client);
      final now = DateTime.now();
      for (final room in roomsToSync) {
        final local = rankingFor(
          room.id,
          sessions,
          now: now,
          currentUserName: displayName,
        );
        final remote = await api.heartbeat(
          roomId: room.id,
          displayName: displayName,
          weeklySeconds: local.userWeeklySeconds,
          sessionCount: local.userSessionCount,
          active: active,
          startedAt: active ? now : null,
        );
        _remoteRankings[room.id] = _rankingFromRemote(remote, room, now);
      }
      if (!_globalLoading) {
        await _refreshGlobalRanking(api);
      }
      _markRemoteRankingSuccess();
    } catch (e) {
      _markRemoteRankingFailure(e, fallbackMessage: '自习室服务暂不可用，请稍后重试或联系管理员。');
    } finally {
      _remoteLoading = false;
      notifyListeners();
    }
  }

  void watchRealtimeRankings({int intervalSeconds = 15}) {
    final client = apiClientGetter?.call();
    if (client == null || client.token == null || client.token!.isEmpty) {
      _realtimeClientKey = null;
      _fallbackToLocal = false;
      _realtimeFailureCount = 0;
      _realtimeRetryAfter = null;
      _cancelAllRealtimeRankings();
      return;
    }
    final clientKey = '${client.baseUrl}|${client.token}';
    if (_realtimeClientKey != clientKey) {
      _realtimeClientKey = clientKey;
      _realtimeRetryAfter = null;
      _realtimeFailureCount = 0;
      _cancelAllRealtimeRankings(notify: false);
    }
    final retryAfter = _realtimeRetryAfter;
    if (retryAfter != null && DateTime.now().isBefore(retryAfter)) {
      return;
    }
    var changed = false;
    final activeIds = joinedRooms.map((room) => room.id).toSet();
    for (final roomId in _rankingEventSubscriptions.keys.toList()) {
      if (!activeIds.contains(roomId)) {
        _cancelRealtimeRanking(roomId);
        changed = true;
      }
    }
    final api = FocusRoomApi(client);
    for (final room in joinedRooms) {
      if (_rankingEventSubscriptions.containsKey(room.id)) continue;
      changed = true;
      late final StreamSubscription<FocusRoomRemoteRanking> subscription;
      subscription = api
          .realtimeRankingEvents(room.id, intervalSeconds: intervalSeconds)
          .listen(
            (remote) {
              final currentRoom =
                  roomById(remote.roomId.isEmpty ? room.id : remote.roomId) ??
                  room;
              _remoteRankings[room.id] = _rankingFromRemote(
                remote,
                currentRoom,
                DateTime.now(),
              );
              _lastRemoteError = null;
              _lastRemoteSyncAt = DateTime.now();
              _markRemoteRankingSuccess(realtime: true);
              _queueRealtimeNotify();
            },
            onError: (Object e, StackTrace stackTrace) {
              if (identical(
                _rankingEventSubscriptions[room.id],
                subscription,
              )) {
                _rankingEventSubscriptions.remove(room.id);
              }
              if (_markRealtimeRankingFailure(
                e,
                client: client,
                stackTrace: stackTrace,
                label: 'room realtime ranking failed',
              )) {
                _queueRealtimeNotify();
              }
            },
            onDone: () {
              if (identical(
                _rankingEventSubscriptions[room.id],
                subscription,
              )) {
                _rankingEventSubscriptions.remove(room.id);
                _queueRealtimeNotify();
              }
            },
            cancelOnError: true,
          );
      _rankingEventSubscriptions[room.id] = subscription;
    }
    if (_globalRankingEventSubscription == null) {
      changed = true;
      late final StreamSubscription<FocusRoomRemoteRanking> subscription;
      subscription = api
          .realtimeGlobalRankingEvents(intervalSeconds: intervalSeconds)
          .listen(
            (remote) {
              _remoteGlobalRanking = _socialRankingFromRemote(
                FocusLeaderboardScope.global,
                remote,
                DateTime.now(),
              );
              _lastRemoteError = null;
              _lastGlobalSyncAt = DateTime.now();
              _markRemoteRankingSuccess(realtime: true);
              _queueRealtimeNotify();
            },
            onError: (Object e, StackTrace stackTrace) {
              if (identical(_globalRankingEventSubscription, subscription)) {
                _globalRankingEventSubscription = null;
              }
              if (_markRealtimeRankingFailure(
                e,
                client: client,
                stackTrace: stackTrace,
                label: 'global realtime ranking failed',
              )) {
                _queueRealtimeNotify();
              }
            },
            onDone: () {
              if (identical(_globalRankingEventSubscription, subscription)) {
                _globalRankingEventSubscription = null;
                _queueRealtimeNotify();
              }
            },
            cancelOnError: true,
          );
      _globalRankingEventSubscription = subscription;
    }
    if (changed) {
      notifyListeners();
    }
  }

  void _queueRealtimeNotify() {
    _realtimeNotifyDebounce?.cancel();
    _realtimeNotifyDebounce = Timer(const Duration(milliseconds: 120), () {
      _realtimeNotifyDebounce = null;
      notifyListeners();
    });
  }

  void stopRealtimeRankings() {
    _cancelAllRealtimeRankings(notify: false);
  }

  Future<void> loadRemoteRanking(
    String roomId,
    Iterable<PomodoroSession> sessions, {
    String currentUserName = '我',
  }) async {
    final client = apiClientGetter?.call();
    final room = roomById(roomId);
    if (client == null ||
        client.token == null ||
        client.token!.isEmpty ||
        room == null) {
      return;
    }
    _remoteLoading = true;
    _lastRemoteError = null;
    notifyListeners();

    try {
      final remote = await FocusRoomApi(client).ranking(roomId);
      _remoteRankings[roomId] = _rankingFromRemote(
        remote,
        room,
        DateTime.now(),
      );
      _lastRemoteSyncAt = DateTime.now();
      _markRemoteRankingSuccess();
    } catch (e) {
      _markRemoteRankingFailure(e, fallbackMessage: '自习室服务暂不可用，请稍后重试或联系管理员。');
    } finally {
      _remoteLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadFocusFriendsAndRanking({bool force = false}) async {
    final client = apiClientGetter?.call();
    if (client == null || client.token == null || client.token!.isEmpty) {
      return;
    }
    if (_friendLoading) return;
    final last = _lastFriendSyncAt;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < _friendRefreshInterval) {
      return;
    }
    _friendLoading = true;
    _lastRemoteError = null;
    notifyListeners();
    try {
      final api = FocusRoomApi(client);
      await _refreshFocusFriendsAndRanking(api);
      _markRemoteRankingSuccess();
    } catch (e) {
      _markRemoteRankingFailure(e, fallbackMessage: '自习室服务暂不可用，请稍后重试或联系管理员。');
    } finally {
      _friendLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadGlobalRanking({bool force = false}) async {
    final client = apiClientGetter?.call();
    if (client == null || client.token == null || client.token!.isEmpty) {
      return;
    }
    if (_globalLoading) return;
    final last = _lastGlobalSyncAt;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < _globalRefreshInterval) {
      return;
    }
    _globalLoading = true;
    _lastRemoteError = null;
    notifyListeners();
    try {
      final api = FocusRoomApi(client);
      await _refreshGlobalRanking(api);
      _markRemoteRankingSuccess();
    } catch (e) {
      _markRemoteRankingFailure(e, fallbackMessage: '自习室服务暂不可用，请稍后重试或联系管理员。');
    } finally {
      _globalLoading = false;
      notifyListeners();
    }
  }

  Future<FocusFriend> addFocusFriend(String username) async {
    final clean = username.trim();
    if (clean.isEmpty) {
      throw const ApiException('请输入好友用户名');
    }
    final client = apiClientGetter?.call();
    if (client == null || client.token == null || client.token!.isEmpty) {
      throw const ApiException('请先登录后再添加专注好友');
    }
    _friendLoading = true;
    _lastRemoteError = null;
    notifyListeners();
    try {
      final api = FocusRoomApi(client);
      final friend = await api.addFriend(username: clean);
      await _refreshFocusFriendsAndRanking(api);
      return friend;
    } catch (e) {
      _lastRemoteError = _focusRoomRemoteError(
        e,
        fallbackMessage: '自习室服务暂不可用，请稍后重试或联系管理员。',
      );
      rethrow;
    } finally {
      _friendLoading = false;
      notifyListeners();
    }
  }

  Future<FocusFriend> acceptFocusFriendRequest(String requesterUserId) async {
    final clean = requesterUserId.trim();
    if (clean.isEmpty) {
      throw const ApiException('好友申请不存在');
    }
    final client = apiClientGetter?.call();
    if (client == null || client.token == null || client.token!.isEmpty) {
      throw const ApiException('请先登录后再处理专注好友申请');
    }
    _friendLoading = true;
    _lastRemoteError = null;
    notifyListeners();
    try {
      final api = FocusRoomApi(client);
      final friend = await api.acceptFriendRequest(clean);
      await _refreshFocusFriendsAndRanking(api);
      return friend;
    } catch (e) {
      _lastRemoteError = _focusRoomRemoteError(
        e,
        fallbackMessage: '自习室服务暂不可用，请稍后重试或联系管理员。',
      );
      rethrow;
    } finally {
      _friendLoading = false;
      notifyListeners();
    }
  }

  Future<void> rejectFocusFriendRequest(String requesterUserId) async {
    final clean = requesterUserId.trim();
    if (clean.isEmpty) {
      throw const ApiException('好友申请不存在');
    }
    final client = apiClientGetter?.call();
    if (client == null || client.token == null || client.token!.isEmpty) {
      throw const ApiException('请先登录后再处理专注好友申请');
    }
    _friendLoading = true;
    _lastRemoteError = null;
    notifyListeners();
    try {
      final api = FocusRoomApi(client);
      await api.rejectFriendRequest(clean);
      await _refreshFocusFriendsAndRanking(api);
    } catch (e) {
      _lastRemoteError = _focusRoomRemoteError(
        e,
        fallbackMessage: '自习室服务暂不可用，请稍后重试或联系管理员。',
      );
      rethrow;
    } finally {
      _friendLoading = false;
      notifyListeners();
    }
  }

  Future<void> cancelFocusFriendRequest(String friendUserId) async {
    final clean = friendUserId.trim();
    if (clean.isEmpty) {
      throw const ApiException('好友申请不存在');
    }
    final client = apiClientGetter?.call();
    if (client == null || client.token == null || client.token!.isEmpty) {
      throw const ApiException('请先登录后再取消专注好友申请');
    }
    _friendLoading = true;
    _lastRemoteError = null;
    notifyListeners();
    try {
      final api = FocusRoomApi(client);
      await api.cancelFriendRequest(clean);
      await _refreshFocusFriendsAndRanking(api);
    } catch (e) {
      _lastRemoteError = _focusRoomRemoteError(
        e,
        fallbackMessage: '自习室服务暂不可用，请稍后重试或联系管理员。',
      );
      rethrow;
    } finally {
      _friendLoading = false;
      notifyListeners();
    }
  }

  Future<void> removeFocusFriend(String friendUserId) async {
    final clean = friendUserId.trim();
    if (clean.isEmpty) {
      throw const ApiException('好友不存在');
    }
    final client = apiClientGetter?.call();
    if (client == null || client.token == null || client.token!.isEmpty) {
      throw const ApiException('请先登录后再移除专注好友');
    }
    _friendLoading = true;
    _lastRemoteError = null;
    notifyListeners();
    try {
      final api = FocusRoomApi(client);
      await api.removeFriend(clean);
      await _refreshFocusFriendsAndRanking(api);
    } catch (e) {
      _lastRemoteError = _focusRoomRemoteError(
        e,
        fallbackMessage: '自习室服务暂不可用，请稍后重试或联系管理员。',
      );
      rethrow;
    } finally {
      _friendLoading = false;
      notifyListeners();
    }
  }

  FocusSocialRanking socialRankingFor(
    FocusLeaderboardScope scope,
    Iterable<PomodoroSession> sessions, {
    DateTime? now,
    String currentUserName = '我',
  }) {
    if (!_fallbackToLocal &&
        scope == FocusLeaderboardScope.friends &&
        _remoteFriendRanking != null) {
      return _remoteFriendRanking!;
    }
    if (!_fallbackToLocal &&
        scope == FocusLeaderboardScope.global &&
        _remoteGlobalRanking != null) {
      return _remoteGlobalRanking!;
    }
    return buildFocusSocialRanking(
      scope: scope,
      sessions: sessions,
      seedMembers: switch (scope) {
        FocusLeaderboardScope.friends => _friendLeaderboardSeeds,
        FocusLeaderboardScope.global => _globalLeaderboardSeeds,
      },
      now: now ?? DateTime.now(),
      currentUserName: currentUserName,
    );
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      storageKey,
      json.encode({
        'rooms': _rooms.map((room) => room.toJson()).toList(),
        'joinedRoomIds': _joinedRoomIds.toList(),
        'activeRoomId': _activeRoomId,
      }),
    );
  }

  List<FocusRoom> _mergeDefaultRooms(List<FocusRoom> stored) {
    final byId = <String, FocusRoom>{
      for (final room in _defaultRooms) room.id: room,
      for (final room in stored) room.id: room,
    };
    return byId.values.toList();
  }

  void _upsertRoom(FocusRoom room) {
    if (room.id.isEmpty) return;
    final idx = _rooms.indexWhere((item) => item.id == room.id);
    if (idx < 0) {
      _rooms = [..._rooms, room];
      return;
    }
    final existing = _rooms[idx];
    final merged = FocusRoom(
      id: room.id,
      name: room.name,
      description: room.description,
      weeklyTargetSeconds: room.weeklyTargetSeconds,
      accentColor: room.accentColor,
      members: existing.members.isNotEmpty ? existing.members : room.members,
      createdAt: existing.createdAt,
    );
    _rooms = [..._rooms.take(idx), merged, ..._rooms.skip(idx + 1)];
  }

  Future<void> _leaveRemoteRoom(String roomId) async {
    final client = apiClientGetter?.call();
    if (client == null || client.token == null || client.token!.isEmpty) {
      return;
    }
    try {
      final room = roomById(roomId);
      final remote = await FocusRoomApi(client).leave(roomId);
      if (room != null) {
        _remoteRankings[roomId] = _rankingFromRemote(
          remote,
          room,
          DateTime.now(),
        );
      }
    } catch (e) {
      _lastRemoteError = _focusRoomRemoteError(
        e,
        fallbackMessage: '自习室服务暂不可用，请稍后重试或联系管理员。',
      );
    }
  }

  void _cancelRealtimeRanking(String roomId) {
    final subscription = _rankingEventSubscriptions.remove(roomId);
    if (subscription != null) unawaited(subscription.cancel());
  }

  void _cancelAllRealtimeRankings({bool notify = true}) {
    if (_rankingEventSubscriptions.isEmpty &&
        _globalRankingEventSubscription == null) {
      _realtimeNotifyDebounce?.cancel();
      _realtimeNotifyDebounce = null;
      return;
    }
    final subscriptions = _rankingEventSubscriptions.values.toList();
    _rankingEventSubscriptions.clear();
    final globalSubscription = _globalRankingEventSubscription;
    _globalRankingEventSubscription = null;
    _realtimeNotifyDebounce?.cancel();
    _realtimeNotifyDebounce = null;
    for (final subscription in subscriptions) {
      unawaited(subscription.cancel());
    }
    if (globalSubscription != null) unawaited(globalSubscription.cancel());
    if (notify) notifyListeners();
  }

  FocusRoomRanking _rankingFromRemote(
    FocusRoomRemoteRanking remote,
    FocusRoom room,
    DateTime now,
  ) {
    final start = focusRoomWeekStart(now);
    final entries = remote.entries.map((entry) {
      final durationCapped = entry.rawWeeklySeconds > entry.weeklySeconds;
      final flagged = durationCapped || entry.riskFlags.isNotEmpty;
      return FocusRoomRankingEntry(
        id: entry.userId,
        name: entry.displayName,
        weeklySeconds: entry.weeklySeconds,
        rawWeeklySeconds: entry.rawWeeklySeconds,
        sessionCount: entry.sessionCount,
        isCurrentUser: entry.isCurrentUser,
        online: entry.online,
        active: entry.active,
        flagged: flagged,
        flagReason: entry.riskSummary.trim().isNotEmpty
            ? entry.riskSummary.trim()
            : flagged
            ? '服务端已校正异常时长'
            : null,
        rank: entry.rank,
        lastSeenAt: entry.lastSeenAt,
      );
    }).toList();
    FocusRoomRankingEntry? currentUser;
    for (final entry in entries) {
      if (entry.isCurrentUser) {
        currentUser = entry;
        break;
      }
    }
    return FocusRoomRanking(
      room: room,
      entries: entries,
      userWeeklySeconds: currentUser?.weeklySeconds ?? 0,
      userSessionCount: currentUser?.sessionCount ?? 0,
      weekStart: start,
      weekEnd: start.add(const Duration(days: 7)),
      remote: true,
      onlineCount: remote.onlineCount,
      updatedAt: remote.updatedAt,
    );
  }

  FocusSocialRanking _socialRankingFromRemote(
    FocusLeaderboardScope scope,
    FocusRoomRemoteRanking remote,
    DateTime now,
  ) {
    final start = focusRoomWeekStart(now);
    final entries = remote.entries.map((entry) {
      final durationCapped = entry.rawWeeklySeconds > entry.weeklySeconds;
      final flagged = durationCapped || entry.riskFlags.isNotEmpty;
      return FocusRoomRankingEntry(
        id: entry.userId,
        name: entry.displayName,
        weeklySeconds: entry.weeklySeconds,
        rawWeeklySeconds: entry.rawWeeklySeconds,
        sessionCount: entry.sessionCount,
        isCurrentUser: entry.isCurrentUser,
        online: entry.online,
        active: entry.active,
        flagged: flagged,
        flagReason: entry.riskSummary.trim().isNotEmpty
            ? entry.riskSummary.trim()
            : flagged
            ? '服务端已校正异常时长'
            : null,
        rank: entry.rank,
        lastSeenAt: entry.lastSeenAt,
      );
    }).toList();
    return FocusSocialRanking(
      scope: scope,
      entries: entries,
      weekStart: start,
      weekEnd: start.add(const Duration(days: 7)),
      suspiciousEntryCount: entries.where((entry) => entry.flagged).length,
      remote: true,
      onlineCount: remote.onlineCount,
      updatedAt: remote.updatedAt,
    );
  }

  Future<void> _refreshFocusFriendsAndRanking(FocusRoomApi api) async {
    final friends = await api.listFriends();
    final requests = await api.listFriendRequests();
    final ranking = await api.friendRanking();
    _focusFriends = friends;
    _incomingFriendRequests = requests.incoming;
    _outgoingFriendRequests = requests.outgoing;
    _remoteFriendRanking = _socialRankingFromRemote(
      FocusLeaderboardScope.friends,
      ranking,
      DateTime.now(),
    );
    _lastFriendSyncAt = DateTime.now();
  }

  Future<void> _refreshGlobalRanking(FocusRoomApi api) async {
    final ranking = await api.globalRanking();
    _remoteGlobalRanking = _socialRankingFromRemote(
      FocusLeaderboardScope.global,
      ranking,
      DateTime.now(),
    );
    _lastGlobalSyncAt = DateTime.now();
  }

  @override
  void dispose() {
    _cancelAllRealtimeRankings(notify: false);
    _realtimeNotifyDebounce?.cancel();
    super.dispose();
  }
}
