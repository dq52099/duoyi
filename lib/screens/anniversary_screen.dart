import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/anniversary.dart';
import '../providers/anniversary_provider.dart';
import '../core/lunar_calendar.dart';
import '../widgets/app_time_picker.dart';
import '../widgets/empty_state.dart';
import '../widgets/surface_components.dart';

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
        return p.items.where((e) => e.type == AnniversaryType.normal).toList();
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
    showAppModalSheet(
      context: context,
      builder: (_) => AppModalSheet(
        title: '最近 30 天',
        child: up.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('未来 30 天内没有安排')),
              )
            : ListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  ...up.map(
                    (a) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: Color(
                          a.colorValue,
                        ).withValues(alpha: 0.2),
                        child: Text(
                          '${a.daysRemaining}',
                          style: TextStyle(
                            color: Color(a.colorValue),
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                      title: Text(a.title),
                      subtitle: Text(
                        '${a.nextOccurrence.year}-${a.nextOccurrence.month.toString().padLeft(2, '0')}-${a.nextOccurrence.day.toString().padLeft(2, '0')}'
                        '${a.yearsPassed != null ? ' · 第${a.yearsPassed! + 1}次' : ''}',
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  void _showAddDialog(BuildContext context) {
    showAppModalSheet(
      context: context,
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
              builder: (ctx) => AppDialog(
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
      onDismissed: (_) => context.read<AnniversaryProvider>().delete(item.id),
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
        onTap: () => showAppModalSheet(
          context: context,
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
                                          right: 6,
                                        ),
                                        child: Icon(
                                          Icons.push_pin,
                                          size: 14,
                                          color: color,
                                        ),
                                      ),
                                    Expanded(
                                      child: Text(
                                        item.title,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w400,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 6,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: color.withValues(alpha: 0.14),
                                        borderRadius: BorderRadius.circular(4),
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
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.deepOrange.withValues(
                                            alpha: 0.12,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
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
                                isPast ? '已过' : (days == 0 ? '就是今天' : '还有'),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Text(
                                    days == 0 ? '今天' : days.abs().toString(),
                                    style: TextStyle(
                                      fontSize: days == 0 ? 22 : 30,
                                      height: 1,
                                      fontWeight: FontWeight.w400,
                                      color: color,
                                    ),
                                  ),
                                  if (days != 0) ...[
                                    const SizedBox(width: 4),
                                    Text(
                                      '天',
                                      style: TextStyle(
                                        color: color,
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
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
  TimeOfDay _remindTime = const TimeOfDay(hour: 9, minute: 0);

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
    _remindTime = TimeOfDay(
      hour: e?.remindHour ?? 9,
      minute: e?.remindMinute ?? 0,
    );
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
      remindHour: _remindTime.hour,
      remindMinute: _remindTime.minute,
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
    final lunar = LunarCalendar.fromSolar(_date);
    final remindTimeText =
        '${_remindTime.hour.toString().padLeft(2, '0')}:${_remindTime.minute.toString().padLeft(2, '0')}';

    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (_, controller) => AppModalSheet(
        title: widget.editing == null ? '新增纪念' : '编辑纪念',
        scrollController: controller,
        leadingActions: widget.editing == null
            ? const []
            : [
                TextButton(
                  onPressed: () {
                    context.read<AnniversaryProvider>().delete(
                      widget.editing!.id,
                    );
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
          FilledButton(
            onPressed: _save,
            child: Text(widget.editing == null ? '添加' : '保存'),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            const Text(
              '类型',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
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
            const Text(
              '日期类型',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 6),
            SegmentedButton<AnniversaryCalendarType>(
              segments: const [
                ButtonSegment(
                  value: AnniversaryCalendarType.solar,
                  icon: Icon(Icons.wb_sunny_outlined),
                  label: Text('公历'),
                ),
                ButtonSegment(
                  value: AnniversaryCalendarType.lunar,
                  icon: Icon(Icons.nightlight_round),
                  label: Text('农历'),
                ),
              ],
              selected: {_cal},
              onSelectionChanged: (value) => setState(() => _cal = value.first),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                _cal == AnniversaryCalendarType.solar
                    ? Icons.calendar_today_outlined
                    : Icons.nightlight_outlined,
              ),
              title: Text(
                _cal == AnniversaryCalendarType.solar
                    ? '公历 ${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}'
                    : '农历 ${_formatLunarDate(lunar)}',
              ),
              subtitle: Text(
                _cal == AnniversaryCalendarType.solar
                    ? '对应农历: ${lunar.toString()}'
                    : '对应公历: ${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                DateTime? picked;
                if (_cal == AnniversaryCalendarType.solar) {
                  picked = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(1900),
                    lastDate: DateTime(2099, 12, 31),
                  );
                } else {
                  picked = await _pickLunarDate(context, lunar);
                }
                if (!mounted) return;
                final pickedDate = picked;
                if (pickedDate != null) setState(() => _date = pickedDate);
              },
            ),
            const SizedBox(height: 8),
            const Text(
              '颜色标识',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
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
                  ? Text('提前 $_remindDays 天 · $remindTimeText')
                  : const Text('关闭'),
              onChanged: (v) => setState(() => _remind = v),
            ),
            if (_remind) ...[
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
                      onChanged: (v) => setState(() => _remindDays = v.toInt()),
                    ),
                  ),
                ],
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule),
                title: const Text('提醒时间'),
                subtitle: Text(remindTimeText),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final picked = await AppTimePicker.show(
                    context,
                    initialTime: _remindTime,
                    title: '提醒时间',
                    minuteStep: 5,
                  );
                  if (picked != null) setState(() => _remindTime = picked);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatLunarDate(LunarDate lunar) {
    final ganzhi = LunarCalendar.ganzhiOf(lunar.year);
    return '$ganzhi年（${lunar.year}）${lunar.chineseText}';
  }

  Future<DateTime?> _pickLunarDate(
    BuildContext context,
    LunarDate initial,
  ) async {
    var year = initial.year;
    var month = initial.month;
    var day = initial.day;
    return showAppModalSheet<DateTime>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          final preview = LunarDate(year, month, day);
          return AppModalSheet(
            title: '选择农历日期',
            subtitle: _formatLunarDate(preview),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(
                  ctx,
                  LunarCalendar.toSolar(year, month, day.clamp(1, 30).toInt()),
                ),
                child: const Text('确定'),
              ),
            ],
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: AppDropdownField<int>(
                        initialValue: year,
                        labelText: '农历年',
                        items: [
                          for (var y = 1900; y <= 2099; y++)
                            DropdownMenuItem(
                              value: y,
                              child: Text('${LunarCalendar.ganzhiOf(y)}年（$y）'),
                            ),
                        ],
                        onChanged: (v) {
                          if (v != null) setSt(() => year = v);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AppDropdownField<int>(
                        initialValue: month,
                        labelText: '月份',
                        items: [
                          for (var m = 1; m <= 12; m++)
                            DropdownMenuItem(
                              value: m,
                              child: Text(LunarDate(year, m, 1).chineseText),
                            ),
                        ],
                        onChanged: (v) {
                          if (v != null) setSt(() => month = v);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                AppDropdownField<int>(
                  initialValue: day,
                  labelText: '日期',
                  items: [
                    for (var d = 1; d <= 30; d++)
                      DropdownMenuItem(
                        value: d,
                        child: Text(LunarDate(year, month, d).dayChineseText),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) setSt(() => day = v);
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
