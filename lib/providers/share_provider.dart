import 'package:flutter/foundation.dart';

import '../models/workspace.dart';
import '../services/api_client.dart';

class ShareProvider extends ChangeNotifier {
  static const _serviceUnavailableMessage = '共享空间服务暂不可用，请稍后重试或联系管理员';
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
  String? _lastError;
  String? _activeWorkspaceId;
  int _accountGeneration = 0;
  Future<void>? _loadInFlight;
  bool _loadInFlightNotifiesLoading = false;
  bool _suppressLoadLoadingNotification = false;
  DateTime? _lastLoadedAt;

  List<Workspace> get workspaces => List.unmodifiable(_workspaces);
  List<WorkspaceMention> get mentions => List.unmodifiable(_mentions);
  int get unreadMentionCount =>
      _mentions.where((mention) => mention.isUnread).length;
  bool get loading => _loading;
  bool get detailLoading => _detailLoading;
  String? get lastError => _lastError;
  String? get activeWorkspaceId => _activeWorkspaceId;

  Workspace? get activeWorkspace {
    final id = _activeWorkspaceId;
    if (id == null) return null;
    return workspaceById(id);
  }

  String _userVisibleWorkspaceError(Object error) {
    debugPrint('[ShareProvider] $error');
    return userVisibleApiError(
      error,
      fallbackMessage: _serviceUnavailableMessage,
    );
  }

  bool _isCurrentAccountGeneration(int generation) =>
      generation == _accountGeneration;

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
    _accountGeneration++;
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
    return WorkspaceRole.owner;
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
    final task = _loadLocked(
      force: force,
      notifyLoading: effectiveNotifyLoading,
    );
    late final Future<void> wrapped;
    wrapped = task.whenComplete(() {
      if (identical(_loadInFlight, wrapped)) {
        _loadInFlight = null;
        _loadInFlightNotifiesLoading = false;
      }
    });
    _loadInFlight = wrapped;
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
  }) async {
    final generation = _accountGeneration;
    final beforeWorkspacesRevision = _workspaceListRevision(_workspaces);
    final beforeMentionsRevision = _mentionListRevision(_mentions);
    final beforeActiveWorkspaceId = _activeWorkspaceId;
    final beforeLastError = _lastError;
    final client = apiClientGetter?.call();
    if (client == null || client.token == null || client.token!.isEmpty) {
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
    try {
      final list = await client.getList('/api/workspaces');
      if (!_isCurrentAccountGeneration(generation)) return;
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
        await _loadMentionInboxFrom(client, generation: generation);
      } catch (_) {
        if (!_isCurrentAccountGeneration(generation)) return;
        _mentions = const <WorkspaceMention>[];
      }
    } catch (e) {
      if (!_isCurrentAccountGeneration(generation)) return;
      _lastError = _userVisibleWorkspaceError(e);
    }
    if (!_isCurrentAccountGeneration(generation)) return;
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
    final generation = _accountGeneration;
    final client = _requireClient();
    _lastError = null;
    try {
      await _loadMentionInboxFrom(client, generation: generation);
    } catch (e) {
      if (!_isCurrentAccountGeneration(generation)) return;
      _lastError = _userVisibleWorkspaceError(e);
    }
    if (!_isCurrentAccountGeneration(generation)) return;
    notifyListeners();
  }

  Future<void> _loadMentionInboxFrom(
    ApiClient client, {
    required int generation,
  }) async {
    final mentions = await client.getList('/api/workspaces/mentions');
    if (!_isCurrentAccountGeneration(generation)) return;
    _mentions = mentions
        .whereType<Map>()
        .map((raw) => WorkspaceMention.fromJson(Map<String, dynamic>.from(raw)))
        .where((mention) => mention.id > 0)
        .toList();
  }

  Future<void> markMentionRead(int mentionId) async {
    final generation = _accountGeneration;
    final client = _requireClient();
    await client.post('/api/workspaces/mentions/$mentionId/read');
    if (!_isCurrentAccountGeneration(generation)) return;
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
    final generation = _accountGeneration;
    final client = _requireClient();
    await client.post('/api/workspaces', {'name': name});
    if (!_isCurrentAccountGeneration(generation)) return;
    await load();
  }

  Future<void> loadWorkspaceCollaboration(String workspaceId) async {
    final generation = _accountGeneration;
    final client = _requireClient();
    _detailLoading = true;
    _lastError = null;
    notifyListeners();
    try {
      final comments = await client.getList(
        '/api/workspaces/$workspaceId/comments',
      );
      if (!_isCurrentAccountGeneration(generation)) return;
      final activities = await client.getList(
        '/api/workspaces/$workspaceId/activities',
      );
      if (!_isCurrentAccountGeneration(generation)) return;
      final leaderboard = await client.getList(
        '/api/workspaces/$workspaceId/leaderboard',
      );
      if (!_isCurrentAccountGeneration(generation)) return;
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
      if (!_isCurrentAccountGeneration(generation)) return;
      _lastError = _userVisibleWorkspaceError(e);
    }
    if (!_isCurrentAccountGeneration(generation)) return;
    _detailLoading = false;
    notifyListeners();
  }

  Future<void> createComment(
    String workspaceId,
    String body, {
    String? targetId,
  }) async {
    final generation = _accountGeneration;
    final client = _requireClient();
    final payload = <String, dynamic>{'body': body};
    if (targetId != null && targetId.isNotEmpty) {
      payload['target_id'] = targetId;
    }
    final res = await client.post(
      '/api/workspaces/$workspaceId/comments',
      payload,
    );
    if (!_isCurrentAccountGeneration(generation)) return;
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
    final client = _requireClient();
    final res = await client.post('/api/workspaces/$workspaceId/invites', {
      'role': role.name,
    });
    return ShareInvite.fromJson(res);
  }

  Future<void> acceptInvite(String code) async {
    final generation = _accountGeneration;
    final client = _requireClient();
    await client.post('/api/invites/${Uri.encodeComponent(code)}/accept');
    if (!_isCurrentAccountGeneration(generation)) return;
    await load();
  }

  Future<void> updateMemberRole(
    String workspaceId,
    String userId,
    WorkspaceRole role,
  ) async {
    final generation = _accountGeneration;
    final client = _requireClient();
    await client.patch('/api/workspaces/$workspaceId/members/$userId', {
      'role': role.name,
    });
    if (!_isCurrentAccountGeneration(generation)) return;
    await load();
  }

  Future<void> removeMember(String workspaceId, String userId) async {
    final generation = _accountGeneration;
    final client = _requireClient();
    await client.delete('/api/workspaces/$workspaceId/members/$userId');
    if (!_isCurrentAccountGeneration(generation)) return;
    await load();
  }

  void setActiveWorkspace(String workspaceId) {
    if (_activeWorkspaceId == workspaceId) return;
    _activeWorkspaceId = workspaceId;
    notifyListeners();
  }

  ApiClient _requireClient() {
    final client = apiClientGetter?.call();
    if (client == null || client.token == null || client.token!.isEmpty) {
      throw const ApiException('请先登录');
    }
    return client;
  }
}
