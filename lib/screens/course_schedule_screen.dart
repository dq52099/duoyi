import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/course_schedule.dart';
import '../providers/course_provider.dart';
import '../widgets/empty_state.dart';
import '../widgets/surface_components.dart';

class CourseScheduleScreen extends StatelessWidget {
  const CourseScheduleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CourseProvider>();
    final settings = provider.settings;
    final week = provider.viewingWeek;
    final courses = provider.coursesOfWeek(week);

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () => _pickWeek(context, provider),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('第 $week 周'),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_drop_down, size: 18),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => provider.setViewingWeek(week - 1),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () => provider.setViewingWeek(week + 1),
          ),
          IconButton(
            icon: const Icon(Icons.today),
            tooltip: '回到本周',
            onPressed: () => provider.setViewingWeek(provider.currentWeek),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => _editSettings(context, provider),
          ),
        ],
      ),
      body: provider.courses.isEmpty
          ? EmptyState(
              icon: Icons.school_outlined,
              message: '添加课表后就能看到你的一周啦',
              actionLabel: '添加课程',
              onAction: () => _addCourse(context, provider),
            )
          : _ScheduleGrid(settings: settings, courses: courses, week: week),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addCourse(context, provider),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _pickWeek(BuildContext context, CourseProvider p) {
    showAppModalSheet(
      context: context,
      builder: (_) => AppModalSheet(
        title: '选择周次',
        subtitle: '切换当前查看的课表周',
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 5,
            childAspectRatio: 2,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: p.settings.totalWeeks,
          itemBuilder: (context, i) {
            final w = i + 1;
            final cs = Theme.of(context).colorScheme;
            final current = w == p.currentWeek;
            final selected = w == p.viewingWeek;
            return OutlinedButton(
              onPressed: () {
                p.setViewingWeek(w);
                Navigator.pop(context);
              },
              style: OutlinedButton.styleFrom(
                backgroundColor: selected
                    ? cs.primary
                    : (current ? cs.primary.withValues(alpha: 0.1) : null),
                foregroundColor: selected ? cs.onPrimary : null,
              ),
              child: Text('第$w周'),
            );
          },
        ),
      ),
    );
  }

  void _editSettings(BuildContext context, CourseProvider p) {
    showAppModalSheet(
      context: context,
      builder: (_) => _ScheduleSettingsSheet(provider: p),
    );
  }

  void _addCourse(BuildContext context, CourseProvider p) {
    showAppModalSheet(
      context: context,
      builder: (_) => _CourseEditSheet(provider: p),
    );
  }
}

class _ScheduleGrid extends StatelessWidget {
  final ScheduleSettings settings;
  final List<CourseItem> courses;
  final int week;

  const _ScheduleGrid({
    required this.settings,
    required this.courses,
    required this.week,
  });

  @override
  Widget build(BuildContext context) {
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    final monday = settings.termStart.add(Duration(days: (week - 1) * 7));
    final today = DateTime.now();

    const sectionH = 56.0;
    const timeW = 34.0;
    final bodyW = MediaQuery.of(context).size.width - timeW;
    final cellW = bodyW / 7;

    return SingleChildScrollView(
      child: Column(
        children: [
          // 顶栏：周几 + 日期
          Row(
            children: [
              SizedBox(width: timeW),
              ...List.generate(7, (i) {
                final d = monday.add(Duration(days: i));
                final isToday =
                    d.year == today.year &&
                    d.month == today.month &&
                    d.day == today.day;
                final cs = Theme.of(context).colorScheme;
                return Expanded(
                  child: Container(
                    height: 48,
                    alignment: Alignment.center,
                    color: isToday ? cs.primary.withValues(alpha: 0.08) : null,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '周${weekdays[i]}',
                          style: TextStyle(
                            fontSize: 12,
                            color: isToday ? cs.primary : null,
                            fontWeight: isToday
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                        Text(
                          '${d.month}/${d.day}',
                          style: TextStyle(
                            fontSize: 11,
                            color: isToday ? cs.primary : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
          const Divider(height: 1),
          // 主体：节数 × 星期
          SizedBox(
            height: sectionH * settings.sessionsPerDay,
            child: Stack(
              children: [
                // 背景：节次+格线
                Row(
                  children: [
                    // 节次列
                    SizedBox(
                      width: timeW,
                      child: Column(
                        children: List.generate(
                          settings.sessionsPerDay,
                          (i) => Container(
                            height: sectionH,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(color: Colors.grey.shade200),
                              ),
                            ),
                            child: Text(
                              '${i + 1}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade500,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // 日格
                    ...List.generate(7, (col) {
                      return Expanded(
                        child: Column(
                          children: List.generate(
                            settings.sessionsPerDay,
                            (row) => Container(
                              height: sectionH,
                              decoration: BoxDecoration(
                                border: Border(
                                  right: BorderSide(
                                    color: Colors.grey.shade200,
                                  ),
                                  bottom: BorderSide(
                                    color: Colors.grey.shade200,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
                // 课程块
                ...courses.map((c) {
                  final col = c.weekday - 1;
                  final row = c.startSection - 1;
                  if (row < 0 || row >= settings.sessionsPerDay) {
                    return const SizedBox.shrink();
                  }
                  return Positioned(
                    left: timeW + col * cellW + 2,
                    top: row * sectionH + 2,
                    width: cellW - 4,
                    height: sectionH * c.sectionCount - 4,
                    child: _CourseBlock(course: c),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CourseBlock extends StatelessWidget {
  final CourseItem course;
  const _CourseBlock({required this.course});

  @override
  Widget build(BuildContext context) {
    final color = Color(course.colorValue);
    final settings = context.read<CourseProvider>().settings;
    final weekPattern = _weekPatternLabel(course.weeks, settings.totalWeeks);
    return GestureDetector(
      onTap: () => showAppModalSheet(
        context: context,
        builder: (_) => _CourseEditSheet(
          provider: context.read<CourseProvider>(),
          course: course,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              settings.sectionTimeRangeLabel(
                course.startSection,
                course.sectionCount,
              ),
              style: const TextStyle(fontSize: 9, color: Colors.white70),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              course.name,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (course.location.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '@${course.location}',
                  style: const TextStyle(fontSize: 10, color: Colors.white70),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (course.teacher.isNotEmpty)
              Text(
                course.teacher,
                style: const TextStyle(fontSize: 10, color: Colors.white70),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            if (weekPattern != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  weekPattern,
                  style: const TextStyle(fontSize: 9, color: Colors.white70),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String? _weekPatternLabel(List<int> weeks, int totalWeeks) {
    if (weeks.isEmpty) return null;
    final normalized = weeks.toSet();
    final all = normalized.length >= totalWeeks;
    if (all) return '全周';
    final oddCount = normalized.where((w) => w.isOdd).length;
    final evenCount = normalized.where((w) => w.isEven).length;
    final expectedOdd = List.generate(
      totalWeeks,
      (i) => i + 1,
    ).where((w) => w.isOdd).length;
    final expectedEven = totalWeeks - expectedOdd;
    if (oddCount == expectedOdd && evenCount == 0) return '单周';
    if (evenCount == expectedEven && oddCount == 0) return '双周';
    return '${normalized.length}周';
  }
}

class _ScheduleSettingsSheet extends StatefulWidget {
  final CourseProvider provider;
  const _ScheduleSettingsSheet({required this.provider});

  @override
  State<_ScheduleSettingsSheet> createState() => _ScheduleSettingsSheetState();
}

class _ScheduleSettingsSheetState extends State<_ScheduleSettingsSheet> {
  late DateTime _termStart;
  late int _totalWeeks;
  late int _sessionsPerDay;
  late int _sessionMinutes;
  late TimeOfDay _firstSessionTime;
  late int _breakMinutes;

  @override
  void initState() {
    super.initState();
    final s = widget.provider.settings;
    _termStart = s.termStart;
    _totalWeeks = s.totalWeeks;
    _sessionsPerDay = s.sessionsPerDay;
    _sessionMinutes = s.sessionMinutes;
    _firstSessionTime = TimeOfDay(
      hour: s.firstSessionHour,
      minute: s.firstSessionMinute,
    );
    _breakMinutes = s.breakMinutes;
  }

  @override
  Widget build(BuildContext context) {
    return AppModalSheet(
      title: '课表设置',
      subtitle: '调整学期起点和显示密度',
      actions: [
        FilledButton(
          onPressed: () {
            widget.provider.updateSettings(
              ScheduleSettings(
                termStart: _termStart,
                totalWeeks: _totalWeeks,
                sessionsPerDay: _sessionsPerDay,
                sessionMinutes: _sessionMinutes,
                firstSessionHour: _firstSessionTime.hour,
                firstSessionMinute: _firstSessionTime.minute,
                breakMinutes: _breakMinutes,
              ),
            );
            Navigator.pop(context);
          },
          child: const Text('保存'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('开学日期 (第 1 周的周一)'),
            subtitle: Text(
              '${_termStart.year}-${_termStart.month.toString().padLeft(2, '0')}-${_termStart.day.toString().padLeft(2, '0')}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _termStart,
                firstDate: DateTime(2020),
                lastDate: DateTime(2099, 12, 31),
              );
              if (picked != null) {
                final monday = picked.subtract(
                  Duration(days: picked.weekday - 1),
                );
                setState(() => _termStart = monday);
              }
            },
          ),
          _sliderRow('总周数', _totalWeeks.toDouble(), 8, 30, 1, (v) {
            setState(() => _totalWeeks = v.toInt());
          }),
          _sliderRow('每天节数', _sessionsPerDay.toDouble(), 4, 14, 1, (v) {
            setState(() => _sessionsPerDay = v.toInt());
          }),
          _sliderRow('每节分钟数', _sessionMinutes.toDouble(), 30, 90, 5, (v) {
            setState(() => _sessionMinutes = v.toInt());
          }),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('第一节开始时间'),
            subtitle: Text(
              '${_firstSessionTime.hour.toString().padLeft(2, '0')}:${_firstSessionTime.minute.toString().padLeft(2, '0')}',
            ),
            trailing: const Icon(Icons.schedule),
            onTap: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: _firstSessionTime,
              );
              if (picked != null) {
                setState(() => _firstSessionTime = picked);
              }
            },
          ),
          _sliderRow('课间分钟数', _breakMinutes.toDouble(), 0, 30, 5, (v) {
            setState(() => _breakMinutes = v.toInt());
          }),
          const SizedBox(height: 8),
          Text(
            '节次预览：1 ${_previewSettings().sectionTimeLabel(1)} · '
            '2 ${_previewSettings().sectionTimeLabel(2)}',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.62),
            ),
          ),
        ],
      ),
    );
  }

  ScheduleSettings _previewSettings() {
    return ScheduleSettings(
      termStart: _termStart,
      totalWeeks: _totalWeeks,
      sessionsPerDay: _sessionsPerDay,
      sessionMinutes: _sessionMinutes,
      firstSessionHour: _firstSessionTime.hour,
      firstSessionMinute: _firstSessionTime.minute,
      breakMinutes: _breakMinutes,
    );
  }

  Widget _sliderRow(
    String label,
    double value,
    double min,
    double max,
    double step,
    ValueChanged<double> onChange,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: const TextStyle(fontSize: 13)),
          ),
          Expanded(
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: ((max - min) / step).round(),
              label: value.toInt().toString(),
              onChanged: onChange,
            ),
          ),
          SizedBox(width: 36, child: Text(value.toInt().toString())),
        ],
      ),
    );
  }
}

class _CourseEditSheet extends StatefulWidget {
  final CourseProvider provider;
  final CourseItem? course;
  const _CourseEditSheet({required this.provider, this.course});

  @override
  State<_CourseEditSheet> createState() => _CourseEditSheetState();
}

class _CourseEditSheetState extends State<_CourseEditSheet> {
  late TextEditingController _name;
  late TextEditingController _teacher;
  late TextEditingController _location;
  int _weekday = 1;
  int _startSection = 1;
  int _sectionCount = 2;
  List<int> _weeks = [];
  int _colorValue = 0xFF42A5F5;

  static const _presetColors = [
    0xFF42A5F5,
    0xFF66BB6A,
    0xFFFFA726,
    0xFFEF5350,
    0xFFAB47BC,
    0xFF26A69A,
    0xFFEC407A,
    0xFF5C6BC0,
  ];

  @override
  void initState() {
    super.initState();
    final c = widget.course;
    _name = TextEditingController(text: c?.name ?? '');
    _teacher = TextEditingController(text: c?.teacher ?? '');
    _location = TextEditingController(text: c?.location ?? '');
    _weekday = c?.weekday ?? 1;
    _startSection = c?.startSection ?? 1;
    _sectionCount = c?.sectionCount ?? 2;
    _weeks = [...?c?.weeks];
    if (_weeks.isEmpty) {
      _weeks = List.generate(widget.provider.settings.totalWeeks, (i) => i + 1);
    }
    _colorValue = c?.colorValue ?? 0xFF42A5F5;
  }

  @override
  void dispose() {
    _name.dispose();
    _teacher.dispose();
    _location.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.provider.settings;
    return AppModalSheet(
      title: widget.course == null ? '新增课程' : '编辑课程',
      subtitle: '按周次、节次和颜色整理课表',
      leadingActions: widget.course == null
          ? const []
          : [
              TextButton(
                onPressed: () {
                  widget.provider.delete(widget.course!.id);
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
          onPressed: () {
            if (_name.text.trim().isEmpty) return;
            final item = CourseItem(
              id: widget.course?.id,
              name: _name.text.trim(),
              teacher: _teacher.text.trim(),
              location: _location.text.trim(),
              weekday: _weekday,
              startSection: _startSection,
              sectionCount: _sectionCount,
              weeks: _weeks..sort(),
              colorValue: _colorValue,
            );
            if (widget.course == null) {
              widget.provider.add(item);
            } else {
              widget.provider.update(item);
            }
            Navigator.pop(context);
          },
          child: Text(widget.course == null ? '添加' : '保存'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _name,
            autofocus: widget.course == null,
            decoration: const InputDecoration(labelText: '课程名'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _teacher,
            decoration: const InputDecoration(labelText: '教师'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _location,
            decoration: const InputDecoration(labelText: '教室'),
          ),
          const SizedBox(height: 16),
          const Text('星期', style: TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: List.generate(7, (i) {
              final w = i + 1;
              const labels = ['一', '二', '三', '四', '五', '六', '日'];
              return ChoiceChip(
                label: Text('周${labels[i]}'),
                selected: _weekday == w,
                onSelected: (_) => setState(() => _weekday = w),
              );
            }),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _numberPick(
                  label: '第几节开始',
                  helper: settings.sectionTimeLabel(_startSection),
                  value: _startSection,
                  min: 1,
                  max: settings.sessionsPerDay,
                  onChange: (v) => setState(() => _startSection = v),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _numberPick(
                  label: '连上几节',
                  helper: settings.sectionTimeRangeLabel(
                    _startSection,
                    _sectionCount,
                  ),
                  value: _sectionCount,
                  min: 1,
                  max: (settings.sessionsPerDay - _startSection + 1).clamp(
                    1,
                    settings.sessionsPerDay,
                  ),
                  onChange: (v) => setState(() => _sectionCount = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '上课周',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              TextButton(
                onPressed: () => setState(
                  () =>
                      _weeks = List.generate(settings.totalWeeks, (i) => i + 1),
                ),
                child: const Text('全选'),
              ),
              TextButton(
                onPressed: () => setState(
                  () => _weeks = List.generate(
                    settings.totalWeeks,
                    (i) => i + 1,
                  ).where((w) => w.isOdd).toList(),
                ),
                child: const Text('单周'),
              ),
              TextButton(
                onPressed: () => setState(
                  () => _weeks = List.generate(
                    settings.totalWeeks,
                    (i) => i + 1,
                  ).where((w) => w.isEven).toList(),
                ),
                child: const Text('双周'),
              ),
              TextButton(
                onPressed: () => setState(() => _weeks = []),
                child: const Text('清空'),
              ),
            ],
          ),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: List.generate(settings.totalWeeks, (i) {
              final w = i + 1;
              final selected = _weeks.contains(w);
              return FilterChip(
                label: Text('$w'),
                selected: selected,
                showCheckmark: false,
                onSelected: (_) => setState(() {
                  if (selected) {
                    _weeks.remove(w);
                  } else {
                    _weeks.add(w);
                  }
                }),
              );
            }),
          ),
          const SizedBox(height: 14),
          const Text('颜色', style: TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            children: _presetColors.map((v) {
              return GestureDetector(
                onTap: () => setState(() => _colorValue = v),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Color(v),
                    shape: BoxShape.circle,
                    border: v == _colorValue
                        ? Border.all(color: Colors.black, width: 2)
                        : null,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _numberPick({
    required String label,
    String? helper,
    required int value,
    required int min,
    required int max,
    required ValueChanged<int> onChange,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          if (helper != null) ...[
            const SizedBox(height: 2),
            Text(
              helper,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          Row(
            children: [
              IconButton(
                iconSize: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.remove),
                onPressed: value > min ? () => onChange(value - 1) : null,
              ),
              const SizedBox(width: 8),
              Text(
                '$value',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                iconSize: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.add),
                onPressed: value < max ? () => onChange(value + 1) : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
