import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/models/workspace.dart';

void main() {
  final now = DateTime(2026, 5, 15);

  group('WorkspaceRole 权限', () {
    test('owner 与 editor 可编辑，viewer 不可', () {
      expect(WorkspaceRole.owner.canEdit, isTrue);
      expect(WorkspaceRole.editor.canEdit, isTrue);
      expect(WorkspaceRole.viewer.canEdit, isFalse);
    });

    test('workspaceRoleFromJson 合法值', () {
      expect(workspaceRoleFromJson('owner'), WorkspaceRole.owner);
      expect(workspaceRoleFromJson('editor'), WorkspaceRole.editor);
      expect(workspaceRoleFromJson('viewer'), WorkspaceRole.viewer);
    });

    test('workspaceRoleFromJson 非法值降级为 viewer', () {
      expect(workspaceRoleFromJson(null), WorkspaceRole.viewer);
      expect(workspaceRoleFromJson(''), WorkspaceRole.viewer);
      expect(workspaceRoleFromJson('unknown'), WorkspaceRole.viewer);
    });
  });

  group('Workspace.roleFor', () {
    test('成员列表为空时，owner 用户得到 owner，其他得到 viewer', () {
      final ws = Workspace(
        id: 'w1',
        name: 'Team',
        ownerUserId: 'u_owner',
        isPrivate: false,
        createdAt: now,
        updatedAt: now,
      );
      expect(ws.roleFor('u_owner'), WorkspaceRole.owner);
      expect(ws.roleFor('u_other'), WorkspaceRole.viewer);
      expect(ws.roleFor(null), WorkspaceRole.viewer);
      expect(ws.roleFor(''), WorkspaceRole.viewer);
    });

    test('成员列表中 editor 与 viewer 各得各的角色', () {
      final ws = Workspace(
        id: 'w1',
        name: 'Team',
        ownerUserId: 'u_owner',
        isPrivate: false,
        createdAt: now,
        updatedAt: now,
        members: [
          WorkspaceMember(
            workspaceId: 'w1',
            userId: 'u_editor',
            username: 'Editor',
            role: WorkspaceRole.editor,
            joinedAt: now,
          ),
          WorkspaceMember(
            workspaceId: 'w1',
            userId: 'u_viewer',
            username: 'Viewer',
            role: WorkspaceRole.viewer,
            joinedAt: now,
          ),
        ],
      );
      expect(ws.roleFor('u_editor'), WorkspaceRole.editor);
      expect(ws.roleFor('u_viewer'), WorkspaceRole.viewer);
      expect(ws.roleFor('u_owner'), WorkspaceRole.owner);
    });
  });

  group('Workspace JSON 兼容', () {
    test('roundtrip 完整保留字段', () {
      final ws = Workspace(
        id: 'w1',
        name: 'Team',
        ownerUserId: 'u_owner',
        isPrivate: true,
        createdAt: now,
        updatedAt: now,
        members: [
          WorkspaceMember(
            workspaceId: 'w1',
            userId: 'u_editor',
            username: 'Editor',
            role: WorkspaceRole.editor,
            joinedAt: now,
          ),
        ],
      );
      final encoded = ws.toJson();
      final decoded = Workspace.fromJson(encoded);
      expect(decoded.id, ws.id);
      expect(decoded.name, ws.name);
      expect(decoded.ownerUserId, ws.ownerUserId);
      expect(decoded.isPrivate, isTrue);
      expect(decoded.members.length, 1);
      expect(decoded.members.first.role, WorkspaceRole.editor);
    });

    test('fromJson 缺失字段使用安全默认值', () {
      final ws = Workspace.fromJson({});
      expect(ws.id, '');
      expect(ws.name, '共享空间');
      expect(ws.members, isEmpty);
      expect(ws.isPrivate, isFalse);
    });
  });
}
