import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_client.dart';
import '../widgets/empty_state.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('反馈与许愿'),
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '提交新反馈',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _category,
                    decoration: const InputDecoration(
                      labelText: '分类',
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'feature', child: Text('功能建议')),
                      DropdownMenuItem(value: 'bug', child: Text('问题反馈')),
                      DropdownMenuItem(value: 'wish', child: Text('许愿池')),
                      DropdownMenuItem(value: 'other', child: Text('其他')),
                    ],
                    onChanged: (v) =>
                        setState(() => _category = v ?? 'feature'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _contentCtrl,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: '描述一下你想反馈或希望增加的功能',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: _submit,
                      child: const Text('提交'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '我的反馈',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_items.isEmpty)
            EmptyState(
              icon: Icons.feedback_outlined,
              message: _error ?? '还没有反馈记录',
            )
          else
            ..._items.map((f) {
              final status = (f['status'] ?? 'open').toString();
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            (f['category'] ?? '').toString(),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _statusColor(
                                status,
                              ).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              status,
                              style: TextStyle(
                                color: _statusColor(status),
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        (f['content'] ?? '').toString(),
                        style: const TextStyle(fontSize: 13),
                      ),
                      if ((f['admin_reply'] ?? '').toString().isNotEmpty) ...[
                        const Divider(),
                        Text(
                          '管理员回复',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        Text(
                          (f['admin_reply'] ?? '').toString(),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
