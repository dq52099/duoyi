import 'package:flutter/material.dart';
import '../core/account_ui_copy.dart';

enum AccountDisplayStatus {
  notLoggedIn,
  loggedIn,
  syncing,
  syncFailed,
  localOnly,
}

/// 账号状态标签（用于"我的"页面与个人资料页）。
///
/// 保证文字、图标、背景和无障碍语义的一致性。普通字重，优雅圆角，紧凑适配。
class AccountStatusChip extends StatelessWidget {
  final AccountDisplayStatus status;
  final VoidCallback? onTap;

  const AccountStatusChip({super.key, required this.status, this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final String label;
    final IconData icon;
    final Color color;
    final Color bg;

    switch (status) {
      case AccountDisplayStatus.notLoggedIn:
        label = AccountUiCopy.statusNotLoggedIn;
        icon = Icons.person_outline;
        color = cs.onSurface.withValues(alpha: 0.65);
        bg = cs.surfaceContainerHighest.withValues(alpha: 0.5);
        break;
      case AccountDisplayStatus.localOnly:
        label = AccountUiCopy.statusLocalMode;
        icon = Icons.phonelink_setup_outlined;
        color = cs.secondary;
        bg = cs.secondaryContainer.withValues(alpha: 0.35);
        break;
      case AccountDisplayStatus.syncing:
        label = AccountUiCopy.statusSyncing;
        icon = Icons.sync;
        color = cs.primary;
        bg = cs.primaryContainer.withValues(alpha: 0.35);
        break;
      case AccountDisplayStatus.syncFailed:
        label = AccountUiCopy.statusSyncFailed;
        icon = Icons.sync_problem_outlined;
        color = cs.error;
        bg = cs.errorContainer.withValues(alpha: 0.35);
        break;
      case AccountDisplayStatus.loggedIn:
        label = AccountUiCopy.statusLoggedIn;
        icon = Icons.verified_user_outlined;
        color = cs.primary;
        bg = cs.primaryContainer.withValues(alpha: 0.3);
        break;
    }

    final chip = Container(
      constraints: const BoxConstraints(minHeight: 20, maxWidth: 140),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                color: color,
                fontWeight: FontWeight.normal,
                height: 1.15,
              ),
            ),
          ),
        ],
      ),
    );

    if (onTap == null) {
      return Semantics(label: label, child: chip);
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: chip,
    );
  }
}
