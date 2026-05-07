import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/anniversary.dart';
import '../providers/anniversary_provider.dart';
import '../core/lunar_calendar.dart';
import '../widgets/empty_state.dart';

/// 纪念日 / 生日 / 倒数日 聚合页
class AnniversaryScreen extends StatefulWidget {
  const AnniversaryScreen({super.key});

  @override
  State<AnniversaryScreen> createState() => _AnniversaryScreenState();
}

class _AnniversaryScreenState extends State<AnniversaryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  List<Anniversary> _filter(AnniversaryProvider p, int idx) {
    switch (idx) {
      case 0:
        return p.items;
      case 1:
        return p.items
            .where((e) => e.type == AnniversaryType.birthday)
            .toList();
      case 2:
        return p.items
            .where((e) => e.type == AnniversaryType.memorial)
            .toList();
      case 3:
        return p.items
            .where((e) => e.type == AnniversaryType.normal)
            .toList();
      default:
        return p.items;
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AnniversaryProvider>();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('纪念日 · 生日 · 倒数'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: '全部'),
            Tab(text: '生日'),
            Tab(text: '纪念日'),
            Tab(text: '倒数'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.today),
            tooltip: '最近 30 天',
            onPressed: () => _showUpcoming(context, provider),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabs,
        children: List.generate(4, (i) {
          final list = _filter(provider, i);
          return list.isEmpty
              ? EmptyState(
                  icon: Icons.event,
                  message: '还没有任何纪念',
                  actionLabel: '添加',
                  onAction: () => _showAddDialog(context),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: list.length,
                  itemBuilder: (context, index) =>
                      _AnniversaryCard(item: list[index]),
                );
        }),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('添加'),
        backgroundColor: cs.primary,
      ),
    );
  }

  void _showUpcoming(BuildContext context, AnniversaryProvider p) {
    final up = p.upcoming;
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: up.isEmpty
              ? const SizedBox(
                  height: 120,
                  child: Center(child: Text('未来 30 天内没有安排')),
                )
              : ListView(
                  shrinkWrap: true,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                        '最近 30 天',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    ...up.map((a) => ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Color(a.colorValue).withValues(alpha: 0.2),
                            child: Text(
                              '${a.daysRemaining}',
                              style: TextStyle(
                                color: Color(a.colorValue),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(a.title),
                          subtitle: Text(
                            '${a.nextOccurrence.year}-${a.nextOccurrence.month.toString().padLeft(2, '0')}-${a.nextOccurrence.day.toString().padLeft(2, '0')}'
                            '${a.yearsPassed != null ? ' · 第${a.yearsPassed! + 1}次' : ''}',
                          ),
                        )),
                  ],
                ),
        ),
      ),
    );
  }

  void _showAddDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AnniversaryEditSheet(),
    );
  }
}

class _AnniversaryCard extends StatelessWidget {
  final Anniversary item;
  const _AnniversaryCard({required this.item});

  String _typeLabel() => switch (item.type) {
        AnniversaryType.birthday => '🎂 生日',
        AnniversaryType.memorial => '💞 纪念日',
        AnniversaryType.normal => '⏰ 倒数',
        AnniversaryType.custom => '🔁 自定义',
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = Color(item.colorValue);
    final days = item.daysRemaining;
    final isPast = item.type == AnniversaryType.normal && days < 0;
    final next = item.nextOccurrence;
    final lunar = LunarCalendar.fromSolar(next);

    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        return await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('确认删除？'),
                content: Text('"${item.title}" 将被移除'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('删除'),
                  ),
                ],
              ),
            ) ??
            false;
      },
      onDismissed: (_) =>
          context.read<AnniversaryProvider>().delete(item.id),
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: cs.error,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: GestureDetector(
        onTap: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => _AnniversaryEditSheet(editing: item),
        ),
        onLongPress: () =>
            context.read<AnniversaryProvider>().togglePin(item.id),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: [
                color.withValues(alpha: 0.12),
                color.withValues(alpha: 0.02),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: color.withValues(alpha: 0.2)),
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
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    if (item.isPinned)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                            right: 6),
                                        child: Icon(Icons.push_pin,
                                            size: 14, color: color),
                                      ),
                                    Expanded(
                                      child: Text(
                                        item.title,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  crossAxisAlignment:
                                      WrapCrossAlignment.center,
                                  spacing: 6,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color:
                                            color.withValues(alpha: 0.14),
                                        borderRadius:
                                            BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        _typeLabel(),
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: color,
                                        ),
                                      ),
                                    ),
                                    if (item.calendarType ==
                                        AnniversaryCalendarType.lunar)
                                      Container(
                                        padding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.deepOrange
                                              .withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          '农历',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.deepOrange,
                                          ),
                                        ),
                                      ),
                                    if (item.yearsPassed != null &&
                                        item.yearsPassed! > 0)
                                      Text(
                                        '已 ${item.yearsPassed} 年',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  item.calendarType ==
                                          AnniversaryCalendarType.lunar
                                      ? '下一次: ${next.year}-${next.month}-${next.day} (${lunar.chineseText})'
                                      : '下一次: ${next.year}-${next.month}-${next.day}',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 12,
                                  ),
                                ),
                                if (item.description != null &&
                                    item.description!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      item.description!,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade500,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                isPast
                                    ? '已过'
                                    : (days == 0 ? '就是今天' : '还有'),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                              Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Text(
                                    days == 0
                                        ? '今天'
                                        : days.abs().toString(),
                                    style: TextStyle(
                                      fontSize: days == 0 ? 22 : 30,
                                      height: 1,
                                      fontWeight: FontWeight.bold,
                                      color: color,
                                    ),
                                  ),
                                  if (days != 0) ...[
                                    const SizedBox(width: 4),
                                    Text('天',
                                        style: TextStyle(
                                            color: color,
                                            fontWeight: FontWeight.bold)),
                                  ],
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
      ),
    );
  }
}

class _AnniversaryEditSheet extends StatefulWidget {
  final Anniversary? editing;
  const _AnniversaryEditSheet({this.editing});

  @override
  State<_AnniversaryEditSheet> createState() => _AnniversaryEditSheetState();
}

class _AnniversaryEditSheetState extends State<_AnniversaryEditSheet> {
  late TextEditingController _title;
  late TextEditingController _desc;
  late DateTime _date;
  AnniversaryType _type = AnniversaryType.normal;
  AnniversaryCalendarType _cal = AnniversaryCalendarType.solar;
  int _colorValue = 0xFFE91E63;
  bool _remind = false;
  int _remindDays = 1;

  static const _presetColors = <int>[
    0xFFE91E63,
    0xFFFFA726,
    0xFF66BB6A,
    0xFF42A5F5,
    0xFF7E57C2,
    0xFF26A69A,
    0xFF8D6E63,
    0xFFEF5350,
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    _title = TextEditingController(text: e?.title ?? '');
    _desc = TextEditingController(text: e?.description ?? '');
    _date = e?.originDate ?? DateTime.now().add(const Duration(days: 1));
    _type = e?.type ?? AnniversaryType.normal;
    _cal = e?.calendarType ?? AnniversaryCalendarType.solar;
    _colorValue = e?.colorValue ?? 0xFFE91E63;
    _remind = e?.remind ?? false;
    _remindDays = e?.remindDaysBefore ?? 1;
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  void _save() {
    if (_title.text.trim().isEmpty) return;
    final p = context.read<AnniversaryProvider>();
    final item = Anniversary.create(
      id: widget.editing?.id,
      title: _title.text.trim(),
      description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
      solarDate: _date,
      type: _type,
      calendarType: _cal,
      colorValue: _colorValue,
      isPinned: widget.editing?.isPinned ?? false,
      remind: _remind,
      remindDaysBefore: _remindDays,
      createdAt: widget.editing?.createdAt,
    );
    if (widget.editing == null) {
      p.add(item);
    } else {
      p.update(item);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lunar = LunarCalendar.fromSolar(_date);

    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: ListView(
          controller: controller,
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.editing == null ? '新增纪念' : '编辑纪念',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              autofocus: widget.editing == null,
              decoration: const InputDecoration(
                labelText: '标题',
                hintText: '如：妈妈生日 / 结婚纪念日',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _desc,
              maxLines: 2,
              decoration: const InputDecoration(labelText: '备注 (可选)'),
            ),
            const SizedBox(height: 16),
            const Text('类型',
                style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: AnniversaryType.values.map((t) {
                final label = switch (t) {
                  AnniversaryType.normal => '⏰ 倒数日',
                  AnniversaryType.birthday => '🎂 生日',
                  AnniversaryType.memorial => '💞 纪念日',
                  AnniversaryType.custom => '🔁 自定义',
                };
                return ChoiceChip(
                  label: Text(label),
                  selected: _type == t,
                  onSelected: (_) => setState(() => _type = t),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            const Text('日期类型',
                style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 6),
            Row(
              children: [
                ChoiceChip(
                  label: const Text('公历'),
                  selected: _cal == AnniversaryCalendarType.solar,
                  onSelected: (_) => setState(
                      () => _cal = AnniversaryCalendarType.solar),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('农历'),
                  selected: _cal == AnniversaryCalendarType.lunar,
                  onSelected: (_) => setState(
                      () => _cal = AnniversaryCalendarType.lunar),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today_outlined),
              title: Text(
                '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
              ),
              subtitle: Text('农历: ${lunar.toString()}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(1900),
                  lastDate: DateTime(2099, 12, 31),
                );
                if (picked != null) setState(() => _date = picked);
              },
            ),
            const SizedBox(height: 8),
            const Text('颜色标识',
                style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              children: _presetColors.map((v) {
                final selected = v == _colorValue;
                return GestureDetector(
                  onTap: () => setState(() => _colorValue = v),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Color(v),
                      shape: BoxShape.circle,
                      border: selected
                          ? Border.all(color: Colors.black, width: 2)
                          : null,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _remind,
              title: const Text('到期提醒'),
              subtitle: _remind
                  ? Text('提前 $_remindDays 天')
                  : const Text('关闭'),
              onChanged: (v) => setState(() => _remind = v),
            ),
            if (_remind)
              Row(
                children: [
                  const SizedBox(width: 16),
                  const Text('提前天数:'),
                  Expanded(
                    child: Slider(
                      value: _remindDays.toDouble(),
                      min: 0,
                      max: 30,
                      divisions: 30,
                      label: '$_remindDays',
                      onChanged: (v) =>
                          setState(() => _remindDays = v.toInt()),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _save,
                child: Text(widget.editing == null ? '添加' : '保存'),
              ),
            ),
            if (widget.editing != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () {
                    context
                        .read<AnniversaryProvider>()
                        .delete(widget.editing!.id);
                    Navigator.pop(context);
                  },
                  style:
                      TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('删除'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
