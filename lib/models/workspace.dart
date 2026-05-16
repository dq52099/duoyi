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
