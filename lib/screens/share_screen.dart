import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/workspace.dart';
import '../providers/auth_provider.dart';
import '../providers/share_provider.dart';
import '../widgets/empty_state.dart';
import '../widgets/surface_components.dart';
import 'login_screen.dart';

class ShareScreen extends StatefulWidget {
  const ShareScreen({super.key});

  @override
  State<ShareScreen> createState() => _ShareScreenState();
}

class _ShareScreenState extends State<ShareScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ShareProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final provider = context.watch<ShareProvider>();
    final cs = Theme.of(context).colorScheme;

    if (!auth.state.isLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('共享空间')),
        body: EmptyState(
          icon: Icons.group_outlined,
          message: '登录后可以创建共享空间并邀请成员',
          actionLabel: '登录',
          onAction: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('共享空间'),
        actions: [
          IconButton(
            tooltip: '加入空间',
            onPressed: () => _acceptInvite(context),
            icon: const Icon(Icons.qr_code_2),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: provider.loading ? null : () => provider.load(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => provider.load(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
          children: [
            AppSurfaceCard(
              padding: const EdgeInsets.all(16),
              gradient: LinearGradient(
                colors: [cs.primary.withValues(alpha: 0.12), cs.surface],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(Icons.group_outlined, color: cs.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '共享空间',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '创建空间后，把待办清单共享给家人、朋友或团队成员。',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: cs.onSurface.withValues(alpha: 0.66),
                              ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => _createWorkspace(context),
                    icon: const Icon(Icons.add),
                    label: const Text('新建'),
                  ),
                ],
              ),
            ),
            if (provider.lastError != null) ...[
              const SizedBox(height: 12),
              AppSurfaceCard(
                padding: const EdgeInsets.all(12),
                border: Border.all(color: cs.error.withValues(alpha: 0.32)),
                child: Text(
                  provider.lastError!,
                  style: TextStyle(color: cs.error),
                ),
              ),
            ],
            const AppSectionHeader(
              title: '我的空间',
              subtitle: '拥有者可邀请成员，viewer 只读，editor 可编辑',
            ),
            if (provider.loading)
              const Padding(
                padding: EdgeInsets.all(28),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (provider.workspaces.isEmpty)
              EmptyState(
                icon: Icons.group_add_outlined,
                message: '还没有共享空间',
                actionLabel: '创建空间',
                onAction: () => _createWorkspace(context),
              )
            else
              ...provider.workspaces.map(
                (workspace) => _WorkspaceCard(workspace: workspace),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _createWorkspace(BuildContext context) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AppDialog(
        title: const Text('新建共享空间'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: '空间名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !context.mounted) return;
    try {
      await context.read<ShareProvider>().createWorkspace(name);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('创建失败: $e')));
    }
  }

  Future<void> _acceptInvite(BuildContext context) async {
    final ctrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AppDialog(
        title: const Text('加入共享空间'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: '邀请码'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('加入'),
          ),
        ],
      ),
    );
    if (code == null || code.isEmpty || !context.mounted) return;
    try {
      await context.read<ShareProvider>().acceptInvite(code);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已加入共享空间')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('加入失败: $e')));
    }
  }
}

class _WorkspaceCard extends StatelessWidget {
  final Workspace workspace;

  const _WorkspaceCard({required this.workspace});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final role = workspace.roleFor(auth.state.userId);
    final cs = Theme.of(context).colorScheme;
    final color = workspace.isPrivate ? Colors.blueGrey : cs.primary;
    return AppSurfaceCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      border: Border.all(color: color.withValues(alpha: 0.18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  workspace.isPrivate
                      ? Icons.lock_outline
                      : Icons.groups_2_outlined,
                  color: color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      workspace.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${workspace.members.length} 位成员 · ${role.label}',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.62),
                      ),
                    ),
                  ],
                ),
              ),
              if (!workspace.isPrivate && role.canEdit)
                IconButton(
                  tooltip: '生成邀请码',
                  onPressed: () => _createInvite(context, workspace),
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: workspace.members
                .map(
                  (member) => _MemberChip(member: member, workspace: workspace),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Future<void> _createInvite(BuildContext context, Workspace workspace) async {
    var role = WorkspaceRole.viewer;
    final invite = await showDialog<ShareInvite>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AppDialog(
          title: const Text('生成邀请码'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('只读成员'),
                trailing: role == WorkspaceRole.viewer
                    ? Icon(
                        Icons.check,
                        color: Theme.of(ctx).colorScheme.primary,
                      )
                    : null,
                onTap: () => setSt(() => role = WorkspaceRole.viewer),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('可编辑成员'),
                trailing: role == WorkspaceRole.editor
                    ? Icon(
                        Icons.check,
                        color: Theme.of(ctx).colorScheme.primary,
                      )
                    : null,
                onTap: () => setSt(() => role = WorkspaceRole.editor),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  final created = await context
                      .read<ShareProvider>()
                      .createInvite(workspace.id, role: role);
                  if (ctx.mounted) Navigator.pop(ctx, created);
                } catch (e) {
                  if (!ctx.mounted) return;
                  ScaffoldMessenger.of(
                    ctx,
                  ).showSnackBar(SnackBar(content: Text('生成失败: $e')));
                }
              },
              child: const Text('生成'),
            ),
          ],
        ),
      ),
    );
    if (invite == null || !context.mounted) return;
    await Clipboard.setData(ClipboardData(text: invite.code));
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AppDialog(
        title: const Text('邀请码已复制'),
        content: SelectableText(
          '${invite.code}\n\n角色：${invite.role.label}',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('完成'),
          ),
        ],
      ),
    );
  }
}

class _MemberChip extends StatelessWidget {
  final WorkspaceMember member;
  final Workspace workspace;

  const _MemberChip({required this.member, required this.workspace});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 10,
            backgroundColor: cs.primary.withValues(alpha: 0.14),
            child: Text(
              member.username.isEmpty ? '?' : member.username.substring(0, 1),
              style: TextStyle(fontSize: 10, color: cs.primary),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            member.username.isEmpty ? member.userId : member.username,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 5),
          Text(
            member.role.label,
            style: TextStyle(
              fontSize: 11,
              color: cs.onSurface.withValues(alpha: 0.56),
            ),
          ),
        ],
      ),
    );
  }
}
