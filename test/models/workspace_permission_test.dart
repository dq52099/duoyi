import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/models/workspace.dart';

void main() {
  final now = DateTime(2026, 5, 15);
  late AppLocale savedLocale;

  setUp(() {
    savedLocale = I18n.current;
    I18n.setLocale(AppLocale.zh);
  });
  tearDown(() => I18n.setLocale(savedLocale));

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

    test('role labels localize while permissions and JSON stay stable', () {
      final expected = <WorkspaceRole, List<String>>{
        WorkspaceRole.owner: ['拥有者', 'Owner'],
        WorkspaceRole.editor: ['可编辑', 'Can edit'],
        WorkspaceRole.viewer: ['只读', 'Read only'],
      };
      final workspace = Workspace(
        id: 'w-locale',
        name: '作者空间',
        ownerUserId: 'u-owner',
        isPrivate: false,
        createdAt: now,
        updatedAt: now,
        members: [
          for (final role in WorkspaceRole.values)
            WorkspaceMember(
              workspaceId: 'w-locale',
              userId: 'u-${role.name}',
              username: '作者-${role.name}',
              role: role,
              joinedAt: now,
            ),
        ],
      );
      final encodedBefore = jsonEncode(workspace.toJson());

      for (final locale in AppLocale.values) {
        I18n.setLocale(locale);
        final labelIndex = locale == AppLocale.zh ? 0 : 1;
        for (final entry in expected.entries) {
          expect(entry.key.labelFor(locale), entry.value[labelIndex]);
          expect(entry.key.label, entry.value[labelIndex]);
        }
        expect(WorkspaceRole.values.map((role) => role.canEdit).toList(), [
          true,
          true,
          false,
        ]);
        expect(workspace.members.map((member) => member.role.name).toList(), [
          'owner',
          'editor',
          'viewer',
        ]);
        expect(jsonEncode(workspace.toJson()), encodedBefore);
      }

      I18n.setLocale(AppLocale.en);
      expect(WorkspaceRole.owner.labelFor(AppLocale.zh), '拥有者');
      expect(WorkspaceRole.viewer.labelFor(AppLocale.en), 'Read only');
      expect(I18n.current, AppLocale.en);
      expect(jsonEncode(workspace.toJson()), encodedBefore);
    });
  });

  test(
    'WorkspaceActivity localizes known actions and preserves unknown data',
    () {
      final expected = <String, List<String>>{
        'workspace.create': ['创建了空间', 'Created the workspace'],
        'workspace.invite': ['生成了邀请码', 'Created an invitation code'],
        'workspace.invite.accept': ['加入了空间', 'Joined the workspace'],
        'workspace.member.role': ['调整了成员权限', 'Changed member permissions'],
        'workspace.member.remove': ['移除了成员', 'Removed a member'],
        'workspace.comment': ['发表了评论', 'Posted a comment'],
      };
      final activities = [
        for (final action in expected.keys)
          WorkspaceActivity(
            id: expected.keys.toList().indexOf(action) + 1,
            workspaceId: 'w-locale',
            actorUserId: 'u-author',
            actorName: '作者名字',
            action: action,
            detail: '作者提供的活动详情',
            createdAt: now,
          ),
      ];
      final unknown = WorkspaceActivity(
        id: 99,
        workspaceId: 'w-locale',
        actorUserId: 'u-server',
        actorName: '服务端成员名',
        action: 'workspace.future-action',
        detail: '未经翻译的服务端详情',
        createdAt: now,
      );

      for (final locale in AppLocale.values) {
        I18n.setLocale(locale);
        final labelIndex = locale == AppLocale.zh ? 0 : 1;
        for (final activity in activities) {
          expect(
            activity.labelFor(locale),
            expected[activity.action]![labelIndex],
          );
          expect(activity.label, expected[activity.action]![labelIndex]);
          expect(activity.actorName, '作者名字');
          expect(activity.detail, '作者提供的活动详情');
        }
        expect(unknown.labelFor(locale), 'workspace.future-action');
        expect(unknown.label, 'workspace.future-action');
        expect(unknown.action, 'workspace.future-action');
        expect(unknown.actorName, '服务端成员名');
        expect(unknown.detail, '未经翻译的服务端详情');
      }

      I18n.setLocale(AppLocale.en);
      expect(activities.first.labelFor(AppLocale.zh), '创建了空间');
      expect(unknown.labelFor(AppLocale.zh), 'workspace.future-action');
      expect(I18n.current, AppLocale.en);
    },
  );

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
