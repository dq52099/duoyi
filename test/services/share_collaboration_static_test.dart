import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('共享空间具备评论和动态流链路', () {
    final backend = File('backend/main.py').readAsStringSync();
    final provider = File(
      'lib/providers/share_provider.dart',
    ).readAsStringSync();
    final screen = File('lib/screens/share_screen.dart').readAsStringSync();
    final model = File('lib/models/workspace.dart').readAsStringSync();
    final audit = File('docs/zhijian-time-parity-audit.md').readAsStringSync();

    expect(backend, contains('workspace_comments'));
    expect(backend, contains('workspace_mentions'));
    expect(backend, contains('workspace_activity'));
    expect(backend, contains('workspace_leaderboard'));
    expect(backend, contains('create_workspace_comment'));
    expect(backend, contains('list_workspace_activities'));
    expect(backend, contains('list_workspace_mentions'));
    expect(backend, contains('mark_workspace_mention_read'));
    expect(backend, contains('_send_workspace_mention_email'));
    expect(backend, contains('workspace.mention_email.sent'));
    expect(backend, contains('workspace.mention_email.failed'));
    expect(backend, contains('_extract_workspace_mentions'));
    expect(backend, contains('row["username"]'));
    expect(backend, contains('row["email"]'));
    expect(backend, contains('row["display_name"]'));
    expect(backend, contains('email.split("@", 1)[0]'));
    expect(model, contains('class WorkspaceComment'));
    expect(model, contains('class WorkspaceMention'));
    expect(model, contains('Workspace get asWorkspaceFallback'));
    expect(model, contains('class WorkspaceActivity'));
    expect(model, contains('class WorkspaceLeaderboardEntry'));
    expect(provider, contains('loadWorkspaceCollaboration'));
    expect(provider, contains('loadMentionInbox'));
    expect(provider, contains('leaderboardFor'));
    expect(provider, contains('/leaderboard'));
    expect(provider, contains('/api/workspaces/mentions'));
    expect(provider, contains('markMentionRead'));
    expect(provider, contains('unreadMentionCount'));
    expect(provider, contains('Workspace? workspaceById(String id)'));
    expect(provider, contains('commentsForTarget'));
    expect(provider, contains('createComment'));
    expect(provider, contains('target_id'));
    expect(screen, contains('_MentionInboxButton'));
    expect(screen, contains('_MentionInboxSheet'));
    expect(screen, contains('_MentionTile'));
    expect(screen, contains('_openMentionContext'));
    expect(screen, contains('onOpenMention'));
    expect(screen, contains('markMentionRead(mention.id)'));
    expect(screen, contains('loadWorkspaceCollaboration(mention.workspaceId)'));
    expect(screen, contains('_MentionContextBlock'));
    expect(screen, contains('focusTargetId'));
    expect(screen, contains('focusCommentId'));
    expect(screen, contains('@ 提及'));
    expect(screen, contains('未读提及'));
    expect(screen, contains('_WorkspaceCollaborationSheet'));
    expect(screen, contains('@用户名/邮箱/昵称'));
    expect(screen, contains('协作动态'));
    expect(screen, contains('成员排行榜'));
    expect(screen, contains('_LeaderboardTile'));
    expect(screen, contains('_MemberAvatarStack'));
    expect(screen, contains('_WorkspaceMemberAvatar'));
    expect(screen, contains('_IdentityAvatar'));
    expect(screen, contains('_MemberRoleBadge'));
    expect(screen, contains('_RankBadge'));
    expect(screen, contains('Icons.workspace_premium_outlined'));
    expect(
      screen,
      contains('showRoleRing: visible[i].role == WorkspaceRole.owner'),
    );
    expect(audit, contains('空间评论、动态流、任务负责人选择、任务级评论入口、@ 提及通知'));
    expect(audit, contains('@ 提及邮件提醒'));
    expect(audit, contains('提及收件箱可直接打开对应空间协作上下文'));
    expect(audit, isNot(contains('共享评论/任务分配')));
  });
}
