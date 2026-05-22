import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'surface_components.dart';

class PublicTokenNotice extends StatelessWidget {
  static const groupNumber = '1104138863';
  static const headline = '公益 token2 通知';
  static const message = '公益 token2 通知群 1104138863。希望人人 token 自由，我们永远不会落后。';

  final EdgeInsetsGeometry margin;

  const PublicTokenNotice({super.key, this.margin = EdgeInsets.zero});

  static Future<void> showStartupDialog(BuildContext context) async {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AppDialog(
        icon: const Icon(Icons.campaign_outlined),
        title: const Text(headline),
        content: const _NoticeContent(),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(const ClipboardData(text: groupNumber));
              if (!dialogContext.mounted) return;
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                const SnackBar(
                  content: Text('通知群号已复制'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('复制群号'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFF7C3AED);
    return AppInfoBanner(
      margin: margin,
      icon: Icons.campaign_outlined,
      title: headline,
      message: message,
      color: color,
      onTap: () => showStartupDialog(context),
    );
  }
}

class _NoticeContent extends StatelessWidget {
  const _NoticeContent();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          PublicTokenNotice.message,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: cs.onSurface,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: cs.primaryContainer.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: cs.primary.withValues(alpha: 0.18)),
          ),
          child: const Row(
            children: [
              Icon(Icons.groups_outlined, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '通知群：${PublicTokenNotice.groupNumber}',
                  style: TextStyle(fontWeight: FontWeight.w400),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
