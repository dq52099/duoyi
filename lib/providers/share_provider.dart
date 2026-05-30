import 'package:flutter/foundation.dart';

import '../models/workspace.dart';
import '../services/api_client.dart';

class ShareProvider extends ChangeNotifier {
  static const _serviceUnavailableMessage = '共享空间服务暂不可用，请稍后重试或联系管理员';

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

  Future<void> load() async {
    final client = apiClientGetter?.call();
    if (client == null || client.token == null || client.token!.isEmpty) {
      _workspaces = const <Workspace>[];
      _lastError = null;
      notifyListeners();
      return;
    }
    _loading = true;
    _lastError = null;
    notifyListeners();
    try {
      final list = await client.getList('/api/workspaces');
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
        await _loadMentionInboxFrom(client);
      } catch (_) {
        _mentions = const <WorkspaceMention>[];
      }
    } catch (e) {
      _lastError = _userVisibleWorkspaceError(e);
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> loadMentionInbox() async {
    final client = _requireClient();
    _lastError = null;
    try {
      await _loadMentionInboxFrom(client);
    } catch (e) {
      _lastError = _userVisibleWorkspaceError(e);
    }
    notifyListeners();
  }

  Future<void> _loadMentionInboxFrom(ApiClient client) async {
    final mentions = await client.getList('/api/workspaces/mentions');
    _mentions = mentions
        .whereType<Map>()
        .map((raw) => WorkspaceMention.fromJson(Map<String, dynamic>.from(raw)))
        .where((mention) => mention.id > 0)
        .toList();
  }

  Future<void> markMentionRead(int mentionId) async {
    final client = _requireClient();
    await client.post('/api/workspaces/mentions/$mentionId/read');
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
    final client = _requireClient();
    await client.post('/api/workspaces', {'name': name});
    await load();
  }

  Future<void> loadWorkspaceCollaboration(String workspaceId) async {
    final client = _requireClient();
    _detailLoading = true;
    _lastError = null;
    notifyListeners();
    try {
      final comments = await client.getList(
        '/api/workspaces/$workspaceId/comments',
      );
      final activities = await client.getList(
        '/api/workspaces/$workspaceId/activities',
      );
      final leaderboard = await client.getList(
        '/api/workspaces/$workspaceId/leaderboard',
      );
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
      _lastError = _userVisibleWorkspaceError(e);
    }
    _detailLoading = false;
    notifyListeners();
  }

  Future<void> createComment(
    String workspaceId,
    String body, {
    String? targetId,
  }) async {
    final client = _requireClient();
    final payload = <String, dynamic>{'body': body};
    if (targetId != null && targetId.isNotEmpty) {
      payload['target_id'] = targetId;
    }
    final res = await client.post(
      '/api/workspaces/$workspaceId/comments',
      payload,
    );
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
    final client = _requireClient();
    await client.post('/api/invites/${Uri.encodeComponent(code)}/accept');
    await load();
  }

  Future<void> updateMemberRole(
    String workspaceId,
    String userId,
    WorkspaceRole role,
  ) async {
    final client = _requireClient();
    await client.patch('/api/workspaces/$workspaceId/members/$userId', {
      'role': role.name,
    });
    await load();
  }

  Future<void> removeMember(String workspaceId, String userId) async {
    final client = _requireClient();
    await client.delete('/api/workspaces/$workspaceId/members/$userId');
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
