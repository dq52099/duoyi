import 'package:flutter/material.dart';
import '../core/i18n.dart';
import '../core/i18n_date_format.dart';
import 'package:provider/provider.dart';
import '../models/anniversary.dart';
import '../providers/anniversary_provider.dart';
import '../core/lunar_calendar.dart';
import '../widgets/app_date_picker.dart';
import '../widgets/app_time_picker.dart';
import '../widgets/empty_state.dart';
import '../widgets/surface_components.dart';

Future<void> showAnniversaryEditor(BuildContext context, {Anniversary? item}) {
  return showAppModalSheet<void>(
    context: context,
    builder: (_) => _AnniversaryEditSheet(editing: item),
  );
}

/// 纪念日 / 生日 / 倒数日 聚合页
class AnniversaryScreen extends StatefulWidget {
  final int initialTab;

  const AnniversaryScreen({super.key, this.initialTab = 0});

  @override
  State<AnniversaryScreen> createState() => _AnniversaryScreenState();
}

class _AnniversaryScreenState extends State<AnniversaryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  late int _tabIndex;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 4,
      initialIndex: widget.initialTab.clamp(0, 3),
      vsync: this,
    );
    _tabIndex = _tabs.index;
    _tabs.addListener(_handleTabChanged);
  }

  @override
  void dispose() {
    _tabs.removeListener(_handleTabChanged);
    _tabs.dispose();
    super.dispose();
  }

  void _handleTabChanged() {
    if (_tabIndex == _tabs.index) return;
    setState(() => _tabIndex = _tabs.index);
  }

  String get _title {
    switch (_tabIndex) {
      case 1:
        return I18n.tr('anniversary.birthday');
      case 2:
        return I18n.tr('anniversary.title');
      case 3:
        return I18n.tr('countdown.title');
      default:
        return I18n.tr('anniversary.title');
    }
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
        title: Text(_title),
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: I18n.tr('anniversary.tab.all')),
            Tab(text: I18n.tr('anniversary.birthday')),
            Tab(text: I18n.tr('anniversary.title')),
            Tab(text: I18n.tr('anniversary.countdown_short')),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.today),
            tooltip: I18n.tr('anniversary.upcoming_30_days'),
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
                  message: I18n.tr('anniversary.empty'),
                  actionLabel: I18n.tr('action.add'),
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
        label: Text(I18n.tr('action.add')),
        backgroundColor: cs.primary,
      ),
    );
  }

  void _showUpcoming(BuildContext context, AnniversaryProvider p) {
    final up = p.upcoming;
    showAppModalSheet(
      context: context,
      builder: (_) => AppModalSheet(
        title: I18n.tr('anniversary.upcoming_30_days'),
        child: up.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(I18n.tr('anniversary.upcoming_empty')),
                ),
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
                        '${I18nDateFormat.date(a.nextOccurrence)}'
                        '${a.yearsPassed != null ? ' · ${I18n.tr('anniversary.occurrence.prefix')}${a.yearsPassed! + 1}${I18n.tr('anniversary.occurrence.suffix')}' : ''}',
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  void _showAddDialog(BuildContext context) {
    showAnniversaryEditor(context);
  }
}

class _AnniversaryCard extends StatelessWidget {
  final Anniversary item;
  const _AnniversaryCard({required this.item});

  String _typeLabel() => switch (item.type) {
    AnniversaryType.birthday => '🎂 ${I18n.tr('anniversary.birthday')}',
    AnniversaryType.memorial => '💞 ${I18n.tr('anniversary.title')}',
    AnniversaryType.normal => '⏰ ${I18n.tr('anniversary.countdown_short')}',
    AnniversaryType.custom => '🔁 ${I18n.tr('anniversary.custom')}',
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
                title: Text(I18n.tr('anniversary.delete.title')),
                content: Text(
                  '"${item.title}" ${I18n.tr('anniversary.delete.content_suffix')}',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text(I18n.tr('action.cancel')),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(I18n.tr('action.delete')),
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
        onTap: () => showAnniversaryEditor(context, item: item),
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
                                        child: Text(
                                          I18n.tr('calendar.lunar'),
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: Colors.deepOrange,
                                          ),
                                        ),
                                      ),
                                    if (item.yearsPassed != null &&
                                        item.yearsPassed! > 0)
                                      Text(
                                        '${I18n.tr('anniversary.years_elapsed.prefix')}${item.yearsPassed}${I18n.tr('anniversary.years_elapsed.suffix')}',
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
                                      ? '${I18n.tr('anniversary.next.prefix')}${I18nDateFormat.date(next)} (${I18n.tr('calendar.chinese_lunar')}: ${lunar.chineseText})'
                                      : '${I18n.tr('anniversary.next.prefix')}${I18nDateFormat.date(next)}',
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
                                    ? I18n.tr('countdown.days.elapsed')
                                    : (days == 0
                                          ? I18n.tr('today.anniversary.today')
                                          : I18n.tr(
                                              'countdown.days.remaining',
                                            )),
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
                                    days == 0
                                        ? I18n.tr('anniversary.today_short')
                                        : days.abs().toString(),
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
                                      I18n.tr('unit.day'),
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
    final remindTimeText = I18nDateFormat.timeOfDay(
      hour: _remindTime.hour,
      minute: _remindTime.minute,
    );

    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (_, controller) => AppModalSheet(
        title: widget.editing == null
            ? I18n.tr('anniversary.editor.add_title')
            : I18n.tr('anniversary.editor.edit_title'),
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
                  child: Text(I18n.tr('action.delete')),
                ),
              ],
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(I18n.tr('action.cancel')),
          ),
          FilledButton(
            onPressed: _save,
            child: Text(
              widget.editing == null
                  ? I18n.tr('action.add')
                  : I18n.tr('action.save'),
            ),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _title,
              autofocus: widget.editing == null,
              decoration: InputDecoration(
                labelText: I18n.tr('anniversary.field.title'),
                hintText: I18n.tr('anniversary.field.title_hint'),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _desc,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: I18n.tr('anniversary.field.description'),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              I18n.tr('anniversary.field.type'),
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: AnniversaryType.values.map((t) {
                final label = switch (t) {
                  AnniversaryType.normal =>
                    '⏰ ${I18n.tr('anniversary.countdown_short')}',
                  AnniversaryType.birthday =>
                    '🎂 ${I18n.tr('anniversary.birthday')}',
                  AnniversaryType.memorial =>
                    '💞 ${I18n.tr('anniversary.title')}',
                  AnniversaryType.custom =>
                    '🔁 ${I18n.tr('anniversary.custom')}',
                };
                return ChoiceChip(
                  label: Text(label),
                  selected: _type == t,
                  onSelected: (_) => setState(() => _type = t),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            Text(
              I18n.tr('anniversary.field.date_type'),
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 6),
            SegmentedButton<AnniversaryCalendarType>(
              segments: [
                ButtonSegment(
                  value: AnniversaryCalendarType.solar,
                  icon: const Icon(Icons.wb_sunny_outlined),
                  label: Text(I18n.tr('calendar.solar')),
                ),
                ButtonSegment(
                  value: AnniversaryCalendarType.lunar,
                  icon: const Icon(Icons.nightlight_round),
                  label: Text(I18n.tr('calendar.lunar')),
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
                    ? '${I18n.tr('calendar.solar')} ${I18nDateFormat.date(_date)}'
                    : '${I18n.tr('calendar.chinese_lunar_calendar')} ${_formatLunarDate(lunar)}',
              ),
              subtitle: Text(
                _cal == AnniversaryCalendarType.solar
                    ? '${I18n.tr('calendar.corresponding_lunar')}: ${lunar.toString()}'
                    : '${I18n.tr('calendar.corresponding_solar')}: ${I18nDateFormat.date(_date)}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final result = await AppDatePicker.show(
                  context,
                  initialDate: _date,
                  firstDate: DateTime(1900),
                  lastDate: DateTime(2099, 12, 31),
                  title: I18n.tr('anniversary.field.date_picker_title'),
                  subtitle: I18n.tr('anniversary.field.date_picker_subtitle'),
                  initialMode: _cal == AnniversaryCalendarType.solar
                      ? AppDatePickerMode.solar
                      : AppDatePickerMode.lunar,
                  allowIgnoreYear: _type == AnniversaryType.birthday,
                );
                if (!mounted) return;
                if (result != null) {
                  setState(() {
                    _date = result.date;
                    _cal = result.mode == AppDatePickerMode.solar
                        ? AnniversaryCalendarType.solar
                        : AnniversaryCalendarType.lunar;
                  });
                }
              },
            ),
            const SizedBox(height: 8),
            Text(
              I18n.tr('anniversary.field.color'),
              style: const TextStyle(fontSize: 13, color: Colors.grey),
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
              title: Text(I18n.tr('countdown.field.due_reminder')),
              subtitle: _remind
                  ? Text(
                      '${I18n.tr('countdown.reminder.before_prefix')}$_remindDays${I18n.tr('countdown.reminder.before_suffix')} · $remindTimeText',
                    )
                  : Text(I18n.tr('countdown.reminder.closed')),
              onChanged: (v) => setState(() => _remind = v),
            ),
            if (_remind) ...[
              Row(
                children: [
                  const SizedBox(width: 16),
                  Text('${I18n.tr('countdown.field.remind_days')}:'),
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
                title: Text(I18n.tr('countdown.field.remind_time')),
                subtitle: Text(remindTimeText),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final picked = await AppTimePicker.show(
                    context,
                    initialTime: _remindTime,
                    title: I18n.tr('countdown.field.remind_time'),
                    minuteStep: 5,
                  );
                  if (!mounted) return;
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
    return '$ganzhi${I18n.tr('anniversary.lunar.year_suffix')}（${lunar.year}）${lunar.chineseText}';
  }
}
