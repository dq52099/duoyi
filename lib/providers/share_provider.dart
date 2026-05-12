import 'package:flutter/foundation.dart';

import '../models/workspace.dart';
import '../services/api_client.dart';

class ShareProvider extends ChangeNotifier {
  ApiClient? Function()? apiClientGetter;
  String? Function()? userIdGetter;

  List<Workspace> _workspaces = const <Workspace>[];
  bool _loading = false;
  String? _lastError;
  String? _activeWorkspaceId;

  List<Workspace> get workspaces => List.unmodifiable(_workspaces);
  bool get loading => _loading;
  String? get lastError => _lastError;
  String? get activeWorkspaceId => _activeWorkspaceId;

  Workspace? get activeWorkspace {
    final id = _activeWorkspaceId;
    if (id == null) return null;
    for (final workspace in _workspaces) {
      if (workspace.id == id) return workspace;
    }
    return null;
  }

  WorkspaceRole roleFor(String workspaceId) {
    final userId = userIdGetter?.call();
    for (final workspace in _workspaces) {
      if (workspace.id == workspaceId) return workspace.roleFor(userId);
    }
    return WorkspaceRole.viewer;
  }

  bool canEdit(String? workspaceId) {
    if (workspaceId == null || workspaceId.isEmpty) return true;
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
    } catch (e) {
      _lastError = e.toString();
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> createWorkspace(String name) async {
    final client = _requireClient();
    await client.post('/api/workspaces', {'name': name});
    await load();
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
