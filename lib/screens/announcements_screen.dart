import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/empty_state.dart';

class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await context.read<AuthProvider>().client.getList('/api/announcements');
      _items = list.cast<Map<String, dynamic>>();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _levelColor(String level) {
    switch (level) {
      case 'warning':
        return Colors.orange;
      case 'critical':
        return Colors.red;
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('公告'), backgroundColor: Colors.transparent),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : (_items.isEmpty
                ? EmptyState(
                    icon: Icons.campaign_outlined,
                    message: _error ?? '暂无公告',
                    actionLabel: '刷新',
                    onAction: _load,
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _items.length,
                    itemBuilder: (_, i) {
                      final a = _items[i];
                      final level = (a['level'] ?? 'info').toString();
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: _levelColor(level).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(level,
                                        style: TextStyle(fontSize: 10, color: _levelColor(level))),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      (a['title'] ?? '').toString(),
                                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text((a['body'] ?? '').toString(), style: const TextStyle(fontSize: 13, height: 1.5)),
                              const SizedBox(height: 6),
                              Text((a['created_at'] ?? '').toString(),
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                            ],
                          ),
                        ),
                      );
                    },
                  )),
      ),
    );
  }
}
