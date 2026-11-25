import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/share_ui_copy.dart';
import '../models/workspace.dart';
import '../services/api_client.dart';

class ShareProvider extends ChangeNotifier {
  static const _loadFreshnessWindow = Duration(seconds: 20);

  ApiClient? Function()? apiClientGetter;
  String? Function()? userIdGetter;

  List<Workspace> _workspaces = const <Workspace>[];
  List<WorkspaceMention> _mentions = const <WorkspaceMention>[];
  final Map<String, List<WorkspaceComment>> _commentsByWorkspace = {};
  final Map<String, List<WorkspaceActivity>> _activitiesByWorkspace = {};
  final Map<String, List<WorkspaceLeaderboardEntry>> _leaderboardByWorkspace =
      {};
  bool _loading = false;
  bool _detailLoading = false;
  Object? _lastError;
  String? _activeWorkspaceId;
  int _accountGeneration = 0;
  Future<void>? _loadInFlight;
  bool _loadInFlightNotifiesLoading = false;
  bool _suppressLoadLoadingNotification = false;
  DateTime? _lastLoadedAt;
  bool _disposed = false;
  int _mutationRevision = 0;
  Future<void>? _mutationRefresh;

  List<Workspace> get workspaces => List.unmodifiable(_workspaces);
  List<WorkspaceMention> get mentions => List.unmodifiable(_mentions);
  int get unreadMentionCount =>
      _mentions.where((mention) => mention.isUnread).length;
  bool get loading => _loading;
  bool get detailLoading => _detailLoading;
  String? get lastError {
    final error = _lastError;
    if (error == null) return null;
    return _userVisibleWorkspaceError(error);
  }

  String _userVisibleWorkspaceError(Object error) {
    return ShareUiCopy.error(error);
  }

  String? get activeWorkspaceId => _activeWorkspaceId;

  Workspace? get activeWorkspace {
    final id = _activeWorkspaceId;
    if (id == null) return null;
    return workspaceById(id);
  }

  void _recordError(Object error) {
    debugPrint('[ShareProvider] $error');
    _lastError = error;
  }

  bool _isCurrentAccountGeneration(int generation) =>
      !_disposed && generation == _accountGeneration;

  _ShareRequestOrigin? _captureOrigin() {
    if (_disposed) return null;
    final client = apiClientGetter?.call();
    final token = client?.token;
    if (client == null || token == null || token.isEmpty) return null;
    return _ShareRequestOrigin(
      generation: _accountGeneration,
      client: client,
      token: token,
      baseUrl: client.baseUrl,
      userId: _currentUserId,
    );
  }

  String? get _currentUserId {
    final value = userIdGetter?.call();
    return value == null || value.isEmpty ? null : value;
  }

  _ShareRequestOrigin _requireOrigin() =>
      _captureOrigin() ?? (throw const ApiException('请先登录'));

  bool _isCurrentOrigin(_ShareRequestOrigin origin) {
    if (!_isCurrentAccountGeneration(origin.generation)) return false;
    final current = apiClientGetter?.call();
    // Getters may construct equivalent clients. Compare credentials rather
    // than object identity, and also reject a captured client's mutation.
    if (current == null ||
        current.token != origin.token ||
        current.baseUrl != origin.baseUrl ||
        origin.client.token != origin.token ||
        origin.client.baseUrl != origin.baseUrl) {
      return false;
    }
    // Legacy sessions can receive their first server ID during hydration.
    // Learn it once while the original generation and credentials still match.
    final userId = _currentUserId;
    origin.userId ??= userId;
    return userId == origin.userId;
  }

  Workspace? workspaceById(String id) {
    for (final workspace in _workspaces) {
      if (workspace.id == id) return workspace;
    }
    return null;
  }

  List<WorkspaceComment> commentsFor(String workspaceId) =>
      List.unmodifiable(_commentsByWorkspace[workspaceId] ?? const []);

  List<WorkspaceComment> commentsForTarget(
    String workspaceId,
    String targetId,
  ) {
    return List.unmodifiable(
      (_commentsByWorkspace[workspaceId] ?? const <WorkspaceComment>[]).where(
        (comment) => comment.targetId == targetId,
      ),
    );
  }

  List<WorkspaceActivity> activitiesFor(String workspaceId) =>
      List.unmodifiable(_activitiesByWorkspace[workspaceId] ?? const []);

  List<WorkspaceLeaderboardEntry> leaderboardFor(String workspaceId) =>
      List.unmodifiable(_leaderboardByWorkspace[workspaceId] ?? const []);

  void resetLocalState() {
    if (_disposed) return;
    _accountGeneration++;
    _loadInFlight = null;
    _loadInFlightNotifiesLoading = false;
    _mutationRefresh = null;
    _mutationRevision = 0;
    _workspaces = const <Workspace>[];
    _mentions = const <WorkspaceMention>[];
    _commentsByWorkspace.clear();
    _activitiesByWorkspace.clear();
    _leaderboardByWorkspace.clear();
    _loading = false;
    _detailLoading = false;
    _lastError = null;
    _activeWorkspaceId = null;
    _lastLoadedAt = null;
    notifyListeners();
  }

  WorkspaceRole roleFor(String workspaceId) {
    if (workspaceId.isEmpty || workspaceId == 'private') {
      return WorkspaceRole.owner;
    }
    final userId = userIdGetter?.call();
    for (final workspace in _workspaces) {
      if (workspace.id == workspaceId) return workspace.roleFor(userId);
    }
    return WorkspaceRole.viewer;
  }

  bool canEdit(String? workspaceId) {
    if (workspaceId == null ||
        workspaceId.isEmpty ||
        workspaceId == 'private') {
      return true;
    }
    return roleFor(workspaceId).canEdit;
  }

  Future<void> load({bool force = false, bool notifyLoading = true}) {
    return _load(force: force, notifyLoading: notifyLoading);
  }

  Future<void> _load({
    bool force = false,
    bool notifyLoading = true,
    _ShareRequestOrigin? origin,
  }) {
    if (_disposed || (origin != null && !_isCurrentOrigin(origin))) {
      return Future<void>.value();
    }
    final effectiveNotifyLoading =
        notifyLoading && !_suppressLoadLoadingNotification;
    final inFlight = _loadInFlight;
    if (inFlight != null) {
      if (effectiveNotifyLoading && !_loadInFlightNotifiesLoading) {
        _loadInFlightNotifiesLoading = true;
        if (!_loading || _lastError != null) {
          _loading = true;
          _lastError = null;
          notifyListeners();
        }
      }
      return inFlight;
    }
    _loadInFlightNotifiesLoading = effectiveNotifyLoading;
    // Publish the identity before notifying listeners in _loadLocked; a
    // listener can synchronously join this load or reset the account.
    final completion = Completer<void>();
    final wrapped = completion.future;
    _loadInFlight = wrapped;
    void release() {
      if (identical(_loadInFlight, wrapped)) {
        _loadInFlight = null;
        _loadInFlightNotifiesLoading = false;
      }
    }

    _loadLocked(
      force: force,
      notifyLoading: effectiveNotifyLoading,
      requestOrigin: origin,
    ).then(
      (_) {
        release();
        completion.complete();
      },
      onError: (Object error, StackTrace stack) {
        release();
        completion.completeError(error, stack);
      },
    );
    return wrapped;
  }

  Future<void> _refreshAfterMutation(_ShareRequestOrigin origin) {
    if (!_isCurrentOrigin(origin)) return Future<void>.value();
    _mutationRevision++;
    final existing = _mutationRefresh;
    if (existing != null) return existing;
    final run = () async {
      while (_isCurrentOrigin(origin)) {
        await _loadInFlight;
        if (!_isCurrentOrigin(origin)) return;
        final requiredRevision = _mutationRevision;
        await _load(force: true, origin: origin);
        if (!_isCurrentOrigin(origin) ||
            requiredRevision == _mutationRevision) {
          return;
        }
      }
    }();
    late final Future<void> wrapped;
    wrapped = run.whenComplete(() {
      if (identical(_mutationRefresh, wrapped)) _mutationRefresh = null;
    });
    _mutationRefresh = wrapped;
    return wrapped;
  }

  /// Suppresses loading notifications for loads started synchronously by action.
  Future<T> withoutLoadingNotification<T>(Future<T> Function() action) {
    final previous = _suppressLoadLoadingNotification;
    _suppressLoadLoadingNotification = true;
    try {
      return action();
    } finally {
      _suppressLoadLoadingNotification = previous;
    }
  }

  Future<void> _loadLocked({
    required bool force,
    required bool notifyLoading,
    _ShareRequestOrigin? requestOrigin,
  }) async {
    final generation = _accountGeneration;
    final beforeWorkspacesRevision = _workspaceListRevision(_workspaces);
    final beforeMentionsRevision = _mentionListRevision(_mentions);
    final beforeActiveWorkspaceId = _activeWorkspaceId;
    final beforeLastError = _lastError;
    final origin = requestOrigin ?? _captureOrigin();
    if (origin == null) {
      if (!_isCurrentAccountGeneration(generation)) return;
      final shouldNotify =
          _workspaces.isNotEmpty ||
          _lastError != null ||
          _lastLoadedAt != null ||
          _loading;
      _workspaces = const <Workspace>[];
      _lastError = null;
      _lastLoadedAt = null;
      _loading = false;
      if (shouldNotify) notifyListeners();
      return;
    }
    final loadedAt = _lastLoadedAt;
    if (!force &&
        loadedAt != null &&
        DateTime.now().difference(loadedAt) < _loadFreshnessWindow) {
      return;
    }
    _lastError = null;
    if (notifyLoading) {
      _loading = true;
      notifyListeners();
    }
    if (!_isCurrentOrigin(origin)) return;
    final client = origin.client;
    try {
      final list = await client.getList('/api/workspaces');
      if (!_isCurrentOrigin(origin)) return;
      _workspaces = list
          .whereType<Map>()
          .map((raw) => Workspace.fromJson(Map<String, dynamic>.from(raw)))
          .where((workspace) => workspace.id.isNotEmpty)
          .toList();
      if (_activeWorkspaceId == null ||
          !_workspaces.any((workspace) => workspace.id == _activeWorkspaceId)) {
        _activeWorkspaceId = _workspaces.isEmpty ? null : _workspaces.first.id;
      }
      try {
        await _loadMentionInboxFrom(origin);
      } catch (_) {
        if (!_isCurrentOrigin(origin)) return;
        _mentions = const <WorkspaceMention>[];
      }
    } catch (e) {
      if (!_isCurrentOrigin(origin)) return;
      _recordError(e);
    }
    if (!_isCurrentOrigin(origin)) return;
    if (_lastError == null) {
      _lastLoadedAt = DateTime.now();
    }
    final wasLoading = _loading;
    _loading = false;
    final shouldNotify =
        notifyLoading ||
        wasLoading ||
        beforeWorkspacesRevision != _workspaceListRevision(_workspaces) ||
        beforeMentionsRevision != _mentionListRevision(_mentions) ||
        beforeActiveWorkspaceId != _activeWorkspaceId ||
        beforeLastError != _lastError;
    if (shouldNotify) notifyListeners();
  }

  int _workspaceListRevision(List<Workspace> workspaces) {
    return Object.hashAll(workspaces.map(_workspaceRevision));
  }

  int _workspaceRevision(Workspace workspace) {
    return Object.hash(
      workspace.id,
      workspace.name,
      workspace.ownerUserId,
      workspace.isPrivate,
      workspace.createdAt.millisecondsSinceEpoch,
      workspace.updatedAt.millisecondsSinceEpoch,
      Object.hashAll(workspace.members.map(_workspaceMemberRevision)),
    );
  }

  int _workspaceMemberRevision(WorkspaceMember member) {
    return Object.hash(
      member.workspaceId,
      member.userId,
      member.username,
      member.role.name,
      member.joinedAt.millisecondsSinceEpoch,
    );
  }

  int _mentionListRevision(List<WorkspaceMention> mentions) {
    return Object.hashAll(mentions.map(_mentionRevision));
  }

  int _mentionRevision(WorkspaceMention mention) {
    return Object.hash(
      mention.id,
      mention.workspaceId,
      mention.workspaceName,
      mention.commentId,
      mention.targetId,
      mention.authorUserId,
      mention.authorName,
      mention.body,
      mention.readAt?.millisecondsSinceEpoch,
      mention.createdAt.millisecondsSinceEpoch,
    );
  }

  Future<void> loadMentionInbox() async {
    final origin = _requireOrigin();
    _lastError = null;
    try {
      await _loadMentionInboxFrom(origin);
    } catch (e) {
      if (!_isCurrentOrigin(origin)) return;
      _recordError(e);
    }
    if (!_isCurrentOrigin(origin)) return;
    notifyListeners();
  }

  Future<void> _loadMentionInboxFrom(_ShareRequestOrigin origin) async {
    if (!_isCurrentOrigin(origin)) return;
    final mentions = await origin.client.getList('/api/workspaces/mentions');
    if (!_isCurrentOrigin(origin)) return;
    _mentions = mentions
        .whereType<Map>()
        .map((raw) => WorkspaceMention.fromJson(Map<String, dynamic>.from(raw)))
        .where((mention) => mention.id > 0)
        .toList();
  }

  Future<void> markMentionRead(int mentionId) async {
    final origin = _requireOrigin();
    await origin.client.post('/api/workspaces/mentions/$mentionId/read');
    if (!_isCurrentOrigin(origin)) return;
    _mentions = [
      for (final mention in _mentions)
        if (mention.id == mentionId)
          mention.copyWith(readAt: DateTime.now())
        else
          mention,
    ];
    notifyListeners();
  }

  Future<void> createWorkspace(String name) async {
    final origin = _requireOrigin();
    await origin.client.post('/api/workspaces', {'name': name});
    if (!_isCurrentOrigin(origin)) return;
    await _refreshAfterMutation(origin);
  }

  Future<void> loadWorkspaceCollaboration(String workspaceId) async {
    final origin = _requireOrigin();
    final client = origin.client;
    _detailLoading = true;
    _lastError = null;
    notifyListeners();
    if (!_isCurrentOrigin(origin)) return;
    try {
      final comments = await client.getList(
        '/api/workspaces/$workspaceId/comments',
      );
      if (!_isCurrentOrigin(origin)) return;
      final activities = await client.getList(
        '/api/workspaces/$workspaceId/activities',
      );
      if (!_isCurrentOrigin(origin)) return;
      final leaderboard = await client.getList(
        '/api/workspaces/$workspaceId/leaderboard',
      );
      if (!_isCurrentOrigin(origin)) return;
      _commentsByWorkspace[workspaceId] = comments
          .whereType<Map>()
          .map(
            (raw) => WorkspaceComment.fromJson(Map<String, dynamic>.from(raw)),
          )
          .where((comment) => comment.id.isNotEmpty)
          .toList();
      _activitiesByWorkspace[workspaceId] = activities
          .whereType<Map>()
          .map(
            (raw) => WorkspaceActivity.fromJson(Map<String, dynamic>.from(raw)),
          )
          .where((activity) => activity.action.isNotEmpty)
          .toList();
      _leaderboardByWorkspace[workspaceId] = leaderboard
          .whereType<Map>()
          .map(
            (raw) => WorkspaceLeaderboardEntry.fromJson(
              Map<String, dynamic>.from(raw),
            ),
          )
          .where((entry) => entry.userId.isNotEmpty)
          .toList();
    } catch (e) {
      if (!_isCurrentOrigin(origin)) return;
      _recordError(e);
    }
    if (!_isCurrentOrigin(origin)) return;
    _detailLoading = false;
    notifyListeners();
  }

  Future<void> createComment(
    String workspaceId,
    String body, {
    String? targetId,
  }) async {
    final origin = _requireOrigin();
    final client = origin.client;
    final payload = <String, dynamic>{'body': body};
    if (targetId != null && targetId.isNotEmpty) {
      payload['target_id'] = targetId;
    }
    final res = await client.post(
      '/api/workspaces/$workspaceId/comments',
      payload,
    );
    if (!_isCurrentOrigin(origin)) return;
    final comment = WorkspaceComment.fromJson(res);
    final current = <WorkspaceComment>[
      ...(_commentsByWorkspace[workspaceId] ?? const <WorkspaceComment>[]),
    ];
    current.insert(0, comment);
    _commentsByWorkspace[workspaceId] = current;
    await loadWorkspaceCollaboration(workspaceId);
  }

  Future<ShareInvite> createInvite(
    String workspaceId, {
    WorkspaceRole role = WorkspaceRole.viewer,
  }) async {
    final origin = _requireOrigin();
    final res = await origin.client.post(
      '/api/workspaces/$workspaceId/invites',
      {'role': role.name},
    );
    if (!_isCurrentOrigin(origin)) throw const ApiException('请先登录');
    return ShareInvite.fromJson(res);
  }

  Future<void> acceptInvite(String code) async {
    final origin = _requireOrigin();
    await origin.client.post(
      '/api/invites/${Uri.encodeComponent(code)}/accept',
    );
    if (!_isCurrentOrigin(origin)) return;
    await _refreshAfterMutation(origin);
  }

  Future<void> updateMemberRole(
    String workspaceId,
    String userId,
    WorkspaceRole role,
  ) async {
    final origin = _requireOrigin();
    await origin.client.patch('/api/workspaces/$workspaceId/members/$userId', {
      'role': role.name,
    });
    if (!_isCurrentOrigin(origin)) return;
    await _refreshAfterMutation(origin);
  }

  Future<void> removeMember(String workspaceId, String userId) async {
    final origin = _requireOrigin();
    await origin.client.delete('/api/workspaces/$workspaceId/members/$userId');
    if (!_isCurrentOrigin(origin)) return;
    await _refreshAfterMutation(origin);
  }

  void setActiveWorkspace(String workspaceId) {
    if (_disposed) return;
    if (_activeWorkspaceId == workspaceId) return;
    _activeWorkspaceId = workspaceId;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _accountGeneration++;
    _loadInFlight = null;
    _mutationRefresh = null;
    _loadInFlightNotifiesLoading = false;
    super.dispose();
  }
}

class _ShareRequestOrigin {
  final int generation;
  final ApiClient client;
  final String token;
  final String baseUrl;
  String? userId;

  _ShareRequestOrigin({
    required this.generation,
    required this.client,
    required this.token,
    required this.baseUrl,
    required this.userId,
  });
}
