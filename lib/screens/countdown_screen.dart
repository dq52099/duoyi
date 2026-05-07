import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/countdown_provider.dart';
import '../models/countdown.dart';
import '../widgets/empty_state.dart';

class CountdownScreen extends StatelessWidget {
  const CountdownScreen({super.key});

  void _showAddDialog(BuildContext context) {
    final titleCtrl = TextEditingController();
    DateTime targetDate = DateTime.now().add(const Duration(days: 1));

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('添加倒数日'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: '事件名称 (如: 生日、考试)'),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('目标日期'),
                trailing: Text(
                  '${targetDate.year}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}',
                ),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: targetDate,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    setSt(() => targetDate = picked);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (titleCtrl.text.trim().isNotEmpty) {
                  context.read<CountdownProvider>().addItem(
                    CountdownItem(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      title: titleCtrl.text.trim(),
                      targetDate: targetDate,
                    ),
                  );
                  Navigator.pop(ctx);
                }
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CountdownProvider>();
    final items = provider.items;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('倒数日')),
      body: items.isEmpty
          ? EmptyState(
              icon: Icons.event,
              message: '暂无倒数日记录',
              actionLabel: '添加记录',
              onAction: () => _showAddDialog(context),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final isPast = item.daysRemaining < 0;
                final absDays = item.daysRemaining.abs();
                final color = isPast
                    ? Colors.grey
                    : (item.daysRemaining <= 3 ? Colors.red : cs.primary);

                return Dismissible(
                  key: ValueKey(item.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: cs.error,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: const Icon(
                      Icons.delete_outline,
                      color: Colors.white,
                    ),
                  ),
                  onDismissed: (_) => provider.deleteItem(item.id),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: color.withValues(alpha: 0.2)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: IntrinsicHeight(
                        child: Row(
                          children: [
                            Container(width: 6, color: color),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              if (item.isPinned)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        right: 6,
                                                      ),
                                                  child: Icon(
                                                    Icons.push_pin,
                                                    size: 16,
                                                    color: color,
                                                  ),
                                                ),
                                              Expanded(
                                                child: Text(
                                                  item.title,
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '目标: ${item.targetDate.year}-${item.targetDate.month.toString().padLeft(2, '0')}-${item.targetDate.day.toString().padLeft(2, '0')}',
                                            style: TextStyle(
                                              color: Colors.grey.shade500,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          isPast ? '已过' : '还有',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade500,
                                          ),
                                        ),
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.baseline,
                                          textBaseline: TextBaseline.alphabetic,
                                          children: [
                                            Text(
                                              '$absDays',
                                              style: TextStyle(
                                                fontSize: 32,
                                                fontWeight: FontWeight.bold,
                                                color: color,
                                                height: 1.1,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              '天',
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: color,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}
