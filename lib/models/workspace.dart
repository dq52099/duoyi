enum WorkspaceRole { owner, editor, viewer }

extension WorkspaceRoleX on WorkspaceRole {
  String get label => switch (this) {
    WorkspaceRole.owner => '拥有者',
    WorkspaceRole.editor => '可编辑',
    WorkspaceRole.viewer => '只读',
  };

  bool get canEdit =>
      this == WorkspaceRole.owner || this == WorkspaceRole.editor;
}

WorkspaceRole workspaceRoleFromJson(Object? raw) {
  final value = raw?.toString().toLowerCase();
  return WorkspaceRole.values.firstWhere(
    (role) => role.name == value,
    orElse: () => WorkspaceRole.viewer,
  );
}

class WorkspaceMember {
  final String workspaceId;
  final String userId;
  final String username;
  final WorkspaceRole role;
  final DateTime joinedAt;

  const WorkspaceMember({
    required this.workspaceId,
    required this.userId,
    required this.username,
    required this.role,
    required this.joinedAt,
  });

  Map<String, dynamic> toJson() => {
    'workspace_id': workspaceId,
    'user_id': userId,
    'username': username,
    'role': role.name,
    'joined_at': joinedAt.toIso8601String(),
  };

  factory WorkspaceMember.fromJson(Map<String, dynamic> json) {
    return WorkspaceMember(
      workspaceId: json['workspace_id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      role: workspaceRoleFromJson(json['role']),
      joinedAt:
          DateTime.tryParse(json['joined_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class Workspace {
  final String id;
  final String name;
  final String ownerUserId;
  final bool isPrivate;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<WorkspaceMember> members;

  const Workspace({
    required this.id,
    required this.name,
    required this.ownerUserId,
    required this.isPrivate,
    required this.createdAt,
    required this.updatedAt,
    this.members = const <WorkspaceMember>[],
  });

  WorkspaceRole roleFor(String? userId) {
    if (userId == null || userId.isEmpty) return WorkspaceRole.viewer;
    return members
        .firstWhere(
          (member) => member.userId == userId,
          orElse: () => WorkspaceMember(
            workspaceId: id,
            userId: userId,
            username: '',
            role: ownerUserId == userId
                ? WorkspaceRole.owner
                : WorkspaceRole.viewer,
            joinedAt: createdAt,
          ),
        )
        .role;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'owner_user_id': ownerUserId,
    'is_private': isPrivate,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'members': members.map((m) => m.toJson()).toList(),
  };

  factory Workspace.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return Workspace(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '共享空间',
      ownerUserId: json['owner_user_id']?.toString() ?? '',
      isPrivate: json['is_private'] == true,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? '') ?? now,
      members:
          (json['members'] as List?)
              ?.whereType<Map>()
              .map(
                (raw) =>
                    WorkspaceMember.fromJson(Map<String, dynamic>.from(raw)),
              )
              .toList() ??
          const <WorkspaceMember>[],
    );
  }
}

class ShareInvite {
  final String id;
  final String workspaceId;
  final String code;
  final WorkspaceRole role;
  final DateTime? expiresAt;

  const ShareInvite({
    required this.id,
    required this.workspaceId,
    required this.code,
    required this.role,
    this.expiresAt,
  });

  factory ShareInvite.fromJson(Map<String, dynamic> json) {
    return ShareInvite(
      id: json['id']?.toString() ?? '',
      workspaceId: json['workspace_id']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      role: workspaceRoleFromJson(json['role']),
      expiresAt: DateTime.tryParse(json['expires_at']?.toString() ?? ''),
    );
  }
}

class WorkspaceComment {
  final String id;
  final String workspaceId;
  final String targetId;
  final String authorUserId;
  final String authorName;
  final String body;
  final DateTime createdAt;

  const WorkspaceComment({
    required this.id,
    required this.workspaceId,
    required this.targetId,
    required this.authorUserId,
    required this.authorName,
    required this.body,
    required this.createdAt,
  });

  factory WorkspaceComment.fromJson(Map<String, dynamic> json) {
    return WorkspaceComment(
      id: json['id']?.toString() ?? '',
      workspaceId: json['workspace_id']?.toString() ?? '',
      targetId: json['target_id']?.toString() ?? '',
      authorUserId: json['author_user_id']?.toString() ?? '',
      authorName: json['author_name']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class WorkspaceMention {
  final int id;
  final String workspaceId;
  final String workspaceName;
  final String commentId;
  final String targetId;
  final String authorUserId;
  final String authorName;
  final String body;
  final DateTime? readAt;
  final DateTime createdAt;

  const WorkspaceMention({
    required this.id,
    required this.workspaceId,
    required this.workspaceName,
    required this.commentId,
    required this.targetId,
    required this.authorUserId,
    required this.authorName,
    required this.body,
    required this.readAt,
    required this.createdAt,
  });

  bool get isUnread => readAt == null;

  Workspace get asWorkspaceFallback {
    final now = DateTime.now();
    return Workspace(
      id: workspaceId,
      name: workspaceName.isEmpty ? '共享空间' : workspaceName,
      ownerUserId: '',
      isPrivate: false,
      createdAt: now,
      updatedAt: now,
    );
  }

  WorkspaceMention copyWith({DateTime? readAt}) {
    return WorkspaceMention(
      id: id,
      workspaceId: workspaceId,
      workspaceName: workspaceName,
      commentId: commentId,
      targetId: targetId,
      authorUserId: authorUserId,
      authorName: authorName,
      body: body,
      readAt: readAt ?? this.readAt,
      createdAt: createdAt,
    );
  }

  factory WorkspaceMention.fromJson(Map<String, dynamic> json) {
    return WorkspaceMention(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      workspaceId: json['workspace_id']?.toString() ?? '',
      workspaceName: json['workspace_name']?.toString() ?? '',
      commentId: json['comment_id']?.toString() ?? '',
      targetId: json['target_id']?.toString() ?? '',
      authorUserId: json['author_user_id']?.toString() ?? '',
      authorName: json['author_name']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      readAt: DateTime.tryParse(json['read_at']?.toString() ?? ''),
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class WorkspaceActivity {
  final int id;
  final String workspaceId;
  final String actorUserId;
  final String actorName;
  final String action;
  final String detail;
  final DateTime createdAt;

  const WorkspaceActivity({
    required this.id,
    required this.workspaceId,
    required this.actorUserId,
    required this.actorName,
    required this.action,
    required this.detail,
    required this.createdAt,
  });

  String get label {
    return switch (action) {
      'workspace.create' => '创建了空间',
      'workspace.invite' => '生成了邀请码',
      'workspace.invite.accept' => '加入了空间',
      'workspace.member.role' => '调整了成员权限',
      'workspace.member.remove' => '移除了成员',
      'workspace.comment' => '发表了评论',
      _ => action,
    };
  }

  factory WorkspaceActivity.fromJson(Map<String, dynamic> json) {
    return WorkspaceActivity(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      workspaceId: json['workspace_id']?.toString() ?? '',
      actorUserId: json['actor_user_id']?.toString() ?? '',
      actorName: json['actor_name']?.toString() ?? '',
      action: json['action']?.toString() ?? '',
      detail: json['detail']?.toString() ?? '',
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class WorkspaceLeaderboardEntry {
  final String workspaceId;
  final String userId;
  final String username;
  final WorkspaceRole role;
  final int assigned;
  final int completed;
  final double completionRate;

  const WorkspaceLeaderboardEntry({
    required this.workspaceId,
    required this.userId,
    required this.username,
    required this.role,
    required this.assigned,
    required this.completed,
    required this.completionRate,
  });

  factory WorkspaceLeaderboardEntry.fromJson(Map<String, dynamic> json) {
    return WorkspaceLeaderboardEntry(
      workspaceId: json['workspace_id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      role: workspaceRoleFromJson(json['role']),
      assigned: (json['assigned'] as num?)?.toInt() ?? 0,
      completed: (json['completed'] as num?)?.toInt() ?? 0,
      completionRate: (json['completion_rate'] as num?)?.toDouble() ?? 0,
    );
  }
}
