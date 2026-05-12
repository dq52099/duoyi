import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/api_client.dart';
import '../widgets/empty_state.dart';
import '../widgets/surface_components.dart';

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];
  String? _error;
  String _category = 'feature';
  final _contentCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final auth = context.read<AuthProvider>();
    if (!auth.state.isLoggedIn) {
      setState(() {
        _loading = false;
        _error = '登录后可查看反馈记录';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await auth.client.getList('/api/feedback/me');
      _items = list.cast<Map<String, dynamic>>();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    final text = _contentCtrl.text.trim();
    if (text.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AuthProvider>().client.post('/api/feedback', {
        'category': _category,
        'content': text,
      });
      if (!mounted) return;
      _contentCtrl.clear();
      messenger.showSnackBar(const SnackBar(content: Text('反馈已提交，感谢！')));
      _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'resolved':
        return Colors.green;
      case 'closed':
        return Colors.grey;
      case 'in_progress':
        return Colors.blue;
      default:
        return Colors.orange;
    }
  }

  String _categoryLabel(String category) {
    switch (category) {
      case 'feature':
        return '功能建议';
      case 'bug':
        return '问题反馈';
      case 'wish':
        return '许愿池';
      default:
        return '其他';
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'resolved':
        return '已处理';
      case 'closed':
        return '已关闭';
      case 'in_progress':
        return '处理中';
      default:
        return '待处理';
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('反馈与许愿')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
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
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.feedback_outlined,
                      color: cs.primary,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '反馈与许愿',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: cs.onSurface,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          auth.state.isLoggedIn
                              ? '把功能建议、问题反馈和想要的能力直接写在这里'
                              : '登录后可以提交反馈并查看处理记录',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: cs.onSurface.withValues(alpha: 0.66),
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            AppSettingsSection(
              title: '提交新反馈',
              subtitle: '功能建议、问题反馈或许愿都可以写在这里',
              children: [
                AppDropdownField<String>(
                  initialValue: _category,
                  labelText: '分类',
                  items: const [
                    DropdownMenuItem(value: 'feature', child: Text('功能建议')),
                    DropdownMenuItem(value: 'bug', child: Text('问题反馈')),
                    DropdownMenuItem(value: 'wish', child: Text('许愿池')),
                    DropdownMenuItem(value: 'other', child: Text('其他')),
                  ],
                  onChanged: (v) => setState(() => _category = v ?? 'feature'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _contentCtrl,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: '描述一下你想反馈或希望增加的功能',
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.send_outlined),
                    label: const Text('提交反馈'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AppSectionHeader(
              title: '我的反馈',
              subtitle: _loading ? '正在加载' : _error ?? '最近提交的记录',
              padding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_items.isEmpty)
              EmptyState(
                icon: Icons.feedback_outlined,
                message: _error ?? '还没有反馈记录',
                actionLabel: '刷新',
                onAction: _load,
              )
            else
              ..._items.map((f) {
                final status = (f['status'] ?? 'open').toString();
                final reply = (f['admin_reply'] ?? '').toString();
                final category = _categoryLabel(
                  (f['category'] ?? '').toString(),
                );
                final statusColor = _statusColor(status);

                return AppSurfaceCard(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              category,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: cs.primary,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              _statusLabel(status),
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        (f['content'] ?? '').toString(),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: cs.onSurface,
                          height: 1.45,
                        ),
                      ),
                      if (reply.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '管理员回复',
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(
                                      color: cs.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                reply,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: cs.onSurface.withValues(
                                        alpha: 0.7,
                                      ),
                                      height: 1.45,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
