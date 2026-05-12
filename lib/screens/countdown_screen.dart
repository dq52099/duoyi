import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/countdown_provider.dart';
import '../models/countdown.dart';
import '../widgets/empty_state.dart';
import '../widgets/surface_components.dart';

class CountdownScreen extends StatelessWidget {
  const CountdownScreen({super.key});

  void _showEditor(BuildContext context, {CountdownItem? item}) {
    showAppModalSheet(
      context: context,
      builder: (_) => _CountdownEditSheet(item: item),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CountdownProvider>();
    final items = [...provider.items]
      ..sort((a, b) {
        if (a.isPinned != b.isPinned) {
          return a.isPinned ? -1 : 1;
        }
        return a.daysRemaining.compareTo(b.daysRemaining);
      });
    final cs = Theme.of(context).colorScheme;
    final upcoming = items.where((item) => item.daysRemaining >= 0).toList()
      ..sort((a, b) => a.daysRemaining.compareTo(b.daysRemaining));
    final nearest = upcoming.isNotEmpty ? upcoming.first : null;
    final soonCount = upcoming.where((item) => item.daysRemaining <= 7).length;

    return Scaffold(
      appBar: AppBar(title: const Text('倒数日')),
      body: items.isEmpty
          ? EmptyState(
              icon: Icons.event,
              message: '暂无倒数日记录',
              actionLabel: '添加记录',
              onAction: () => _showEditor(context),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
              children: [
                AppSurfaceCard(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(Icons.event, color: cs.primary, size: 26),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '倒数日',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w400,
                                    color: cs.onSurface,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              nearest == null
                                  ? '暂无即将到期的事件'
                                  : '下一项：${nearest.title} · 还有 ${nearest.daysRemaining} 天',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: cs.onSurface.withValues(alpha: 0.68),
                                  ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                _SummaryStat(
                                  label: '总数',
                                  value: '${items.length}',
                                  color: cs.primary,
                                ),
                                const SizedBox(width: 14),
                                _SummaryStat(
                                  label: '7 天内',
                                  value: '$soonCount',
                                  color: cs.tertiary,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.tonalIcon(
                        onPressed: () => _showEditor(context),
                        icon: const Icon(Icons.add),
                        label: const Text('添加'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const AppSectionHeader(
                  title: '全部倒数日',
                  subtitle: '按优先级和剩余天数排序',
                  padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
                ),
                ...items.map(
                  (item) => _CountdownCard(
                    item: item,
                    onTap: () => _showEditor(context, item: item),
                    onTogglePin: () => provider.togglePin(item.id),
                    onDismissed: () => provider.deleteItem(item.id),
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showEditor(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _CountdownEditSheet extends StatefulWidget {
  final CountdownItem? item;

  const _CountdownEditSheet({this.item});

  @override
  State<_CountdownEditSheet> createState() => _CountdownEditSheetState();
}

class _CountdownEditSheetState extends State<_CountdownEditSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _categoryCtrl;
  late DateTime _targetDate;
  late bool _remind;
  late int _remindDaysBefore;
  late TimeOfDay _remindTime;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _titleCtrl = TextEditingController(text: item?.title ?? '');
    _categoryCtrl = TextEditingController(text: item?.category ?? '默认');
    _targetDate =
        item?.targetDate ?? DateTime.now().add(const Duration(days: 1));
    _remind = item?.remind ?? false;
    _remindDaysBefore = item?.remindDaysBefore ?? 1;
    _remindTime = TimeOfDay(
      hour: item?.remindHour ?? 9,
      minute: item?.remindMinute ?? 0,
    );
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _categoryCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    final category = _categoryCtrl.text.trim().isEmpty
        ? '默认'
        : _categoryCtrl.text.trim();
    final provider = context.read<CountdownProvider>();
    final next = CountdownItem(
      id: widget.item?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      targetDate: _targetDate,
      isPinned: widget.item?.isPinned ?? false,
      category: category,
      remind: _remind,
      remindDaysBefore: _remindDaysBefore,
      remindHour: _remindTime.hour,
      remindMinute: _remindTime.minute,
    );
    if (widget.item == null) {
      provider.addItem(next);
    } else {
      provider.updateItem(next);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final targetText =
        '${_targetDate.year}-${_targetDate.month.toString().padLeft(2, '0')}-${_targetDate.day.toString().padLeft(2, '0')}';
    final timeText =
        '${_remindTime.hour.toString().padLeft(2, '0')}:${_remindTime.minute.toString().padLeft(2, '0')}';
    return AppModalSheet(
      title: widget.item == null ? '添加倒数日' : '编辑倒数日',
      subtitle: '分类、到期日和提醒会同步到日历',
      leadingActions: widget.item == null
          ? const []
          : [
              TextButton(
                onPressed: () {
                  context.read<CountdownProvider>().deleteItem(widget.item!.id);
                  Navigator.pop(context);
                },
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('删除'),
              ),
            ],
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(labelText: '事件名称'),
            autofocus: widget.item == null,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _categoryCtrl,
            decoration: const InputDecoration(labelText: '分类'),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: const Text('目标日期'),
            subtitle: Text(targetText),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _targetDate,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked != null) {
                setState(() => _targetDate = picked);
              }
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _remind,
            title: const Text('到期提醒'),
            subtitle: Text(
              _remind ? '提前 $_remindDaysBefore 天 · $timeText' : '关闭',
            ),
            onChanged: (v) => setState(() => _remind = v),
          ),
          if (_remind) ...[
            Row(
              children: [
                const SizedBox(width: 4),
                const Text('提前天数'),
                Expanded(
                  child: Slider(
                    value: _remindDaysBefore.toDouble(),
                    min: 0,
                    max: 30,
                    divisions: 30,
                    label: '$_remindDaysBefore',
                    onChanged: (v) =>
                        setState(() => _remindDaysBefore = v.toInt()),
                  ),
                ),
              ],
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: const Text('提醒时间'),
              subtitle: Text(timeText),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: _remindTime,
                );
                if (picked != null) {
                  setState(() => _remindTime = picked);
                }
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SummaryStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.numbers, size: 15, color: color),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w400,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurface.withValues(alpha: 0.62),
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

class _CountdownCard extends StatelessWidget {
  final CountdownItem item;
  final VoidCallback onTap;
  final VoidCallback onTogglePin;
  final VoidCallback onDismissed;

  const _CountdownCard({
    required this.item,
    required this.onTap,
    required this.onTogglePin,
    required this.onDismissed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isPast = item.daysRemaining < 0;
    final absDays = item.daysRemaining.abs();
    final color = isPast
        ? Colors.grey
        : (item.daysRemaining <= 3 ? cs.error : cs.primary);
    final status = item.isPinned
        ? '置顶'
        : isPast
        ? '已过期'
        : item.daysRemaining <= 3
        ? '临近'
        : '倒数中';

    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: cs.error,
          borderRadius: BorderRadius.circular(18),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => onDismissed(),
      child: InkWell(
        onTap: onTap,
        onLongPress: onTogglePin,
        borderRadius: BorderRadius.circular(18),
        child: AppSurfaceCard(
          margin: const EdgeInsets.only(bottom: 12),
          padding: EdgeInsets.zero,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.18)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 8,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(18),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (item.isPinned)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: Icon(
                                      Icons.push_pin,
                                      size: 16,
                                      color: color,
                                    ),
                                  ),
                                Expanded(
                                  child: Text(
                                    item.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w400,
                                          color: cs.onSurface,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '目标: ${item.targetDate.year}-${item.targetDate.month.toString().padLeft(2, '0')}-${item.targetDate.day.toString().padLeft(2, '0')}',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: cs.onSurface.withValues(alpha: 0.62),
                                  ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                _StatusPill(label: status, color: color),
                                _StatusPill(
                                  label: item.category,
                                  color: cs.tertiary,
                                ),
                                if (item.remind)
                                  _StatusPill(
                                    label:
                                        '提前${item.remindDaysBefore}天 ${item.remindHour.toString().padLeft(2, '0')}:${item.remindMinute.toString().padLeft(2, '0')}',
                                    color: cs.primary,
                                    icon: Icons.notifications_active_outlined,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            isPast ? '已过' : '还有',
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurface.withValues(alpha: 0.54),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                '$absDays',
                                style: TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w400,
                                  color: color,
                                  height: 1.0,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '天',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: color,
                                  fontWeight: FontWeight.w400,
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
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const _StatusPill({required this.label, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
