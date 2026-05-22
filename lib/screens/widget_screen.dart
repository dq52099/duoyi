import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/android_widget_manager.dart';
import '../services/home_widget_service.dart';
import '../widgets/surface_components.dart';

class WidgetScreen extends StatefulWidget {
  const WidgetScreen({super.key});

  @override
  State<WidgetScreen> createState() => _WidgetScreenState();
}

class _WidgetScreenState extends State<WidgetScreen> {
  static const _displayModeKey = 'duoyi_widget_display_mode';
  _WidgetDisplayMode _displayMode = _WidgetDisplayMode.standard;

  @override
  void initState() {
    super.initState();
    _loadDisplayMode();
  }

  Future<void> _loadDisplayMode() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_displayModeKey);
    if (!mounted) return;
    setState(() {
      _displayMode = _WidgetDisplayMode.fromId(value);
    });
  }

  Future<void> _setDisplayMode(_WidgetDisplayMode mode) async {
    setState(() => _displayMode = mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_displayModeKey, mode.id);
    await HomeWidgetService.setDisplayMode(mode.id);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('小组件样式已切换为${mode.label}')));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('小组件'),
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
        children: [
          AppSurfaceCard(
            padding: const EdgeInsets.all(16),
            color: cs.surface.withValues(alpha: 0.84),
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.teal.withValues(alpha: 0.14),
                  child: const Icon(Icons.widgets_outlined, color: Colors.teal),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '桌面小组件预览',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _WidgetDisplayModePanel(
            value: _displayMode,
            onChanged: _setDisplayMode,
          ),
          const SizedBox(height: 12),
          const _WidgetCatalogTile(
            icon: Icons.checklist_rtl_outlined,
            title: '今日待办',
            subtitle: '展示前三个今日任务，可直接完成或快速添加',
            color: Colors.blue,
          ),
          const SizedBox(height: 10),
          const WidgetPreviewCard.todo(),
          const SizedBox(height: 8),
          _AddWidgetButton(kind: DuoyiWidgetKind.todo),
          const SizedBox(height: 16),
          const _WidgetCatalogTile(
            icon: Icons.timer_outlined,
            title: '专注',
            subtitle: '今日专注次数、专注时长和快速开始',
            color: Colors.redAccent,
          ),
          const SizedBox(height: 10),
          const WidgetPreviewCard.focus(),
          const SizedBox(height: 8),
          _AddWidgetButton(kind: DuoyiWidgetKind.focus),
          const SizedBox(height: 16),
          const _WidgetCatalogTile(
            icon: Icons.self_improvement_outlined,
            title: '习惯',
            subtitle: '今日习惯进度、待打卡习惯和连续记录',
            color: Colors.green,
          ),
          const SizedBox(height: 10),
          const WidgetPreviewCard.habit(),
          const SizedBox(height: 8),
          _AddWidgetButton(kind: DuoyiWidgetKind.habit),
          const SizedBox(height: 16),
          const _WidgetCatalogTile(
            icon: Icons.calendar_month_outlined,
            title: '月历',
            subtitle: '显示本月日期和今日标记',
            color: Colors.indigo,
          ),
          const SizedBox(height: 10),
          const WidgetPreviewCard.calendar(),
          const SizedBox(height: 8),
          _AddWidgetButton(kind: DuoyiWidgetKind.calendar),
          const SizedBox(height: 16),
          const _WidgetCatalogTile(
            icon: Icons.event_note_outlined,
            title: '今日日程',
            subtitle: '展示今天的日程和提醒时间',
            color: Colors.cyan,
          ),
          const SizedBox(height: 10),
          const WidgetPreviewCard.schedule(),
          const SizedBox(height: 8),
          _AddWidgetButton(kind: DuoyiWidgetKind.schedule),
          const SizedBox(height: 16),
          const _WidgetCatalogTile(
            icon: Icons.flag_outlined,
            title: '目标',
            subtitle: '展示进行中目标和进度',
            color: Colors.orange,
          ),
          const SizedBox(height: 10),
          const WidgetPreviewCard.goal(),
          const SizedBox(height: 8),
          _AddWidgetButton(kind: DuoyiWidgetKind.goal),
          const SizedBox(height: 16),
          const _WidgetCatalogTile(
            icon: Icons.school_outlined,
            title: '课程表',
            subtitle: '展示今日课程和下一节课',
            color: Colors.orange,
          ),
          const SizedBox(height: 10),
          const WidgetPreviewCard.course(),
          const SizedBox(height: 8),
          _AddWidgetButton(kind: DuoyiWidgetKind.course),
          const SizedBox(height: 16),
          const _WidgetCatalogTile(
            icon: Icons.edit_note_outlined,
            title: '随手记',
            subtitle: '展示最近更新的三条笔记，点击进入随手记',
            color: Colors.purple,
          ),
          const SizedBox(height: 10),
          const WidgetPreviewCard.note(),
          const SizedBox(height: 8),
          _AddWidgetButton(kind: DuoyiWidgetKind.note),
          const SizedBox(height: 16),
          const _WidgetCatalogTile(
            icon: Icons.event_available_outlined,
            title: '纪念日',
            subtitle: '展示最近的纪念日，点击进入纪念日列表',
            color: Colors.pink,
          ),
          const SizedBox(height: 10),
          const WidgetPreviewCard.anniversary(),
          const SizedBox(height: 8),
          _AddWidgetButton(kind: DuoyiWidgetKind.anniversary),
          const SizedBox(height: 16),
          const _WidgetCatalogTile(
            icon: Icons.book_outlined,
            title: '日记',
            subtitle: '展示最近三篇日记，点击进入日记',
            color: Colors.teal,
          ),
          const SizedBox(height: 10),
          const WidgetPreviewCard.diary(),
          const SizedBox(height: 8),
          _AddWidgetButton(kind: DuoyiWidgetKind.diary),
          const SizedBox(height: 12),
          AppInfoBanner(
            icon: Icons.touch_app_outlined,
            color: Colors.teal,
            message: '在系统桌面长按空白处，选择“小组件”，找到“多仪”后拖到桌面；不支持时会提示你去系统设置。',
          ),
        ],
      ),
    );
  }
}

enum _WidgetDisplayMode {
  compact('compact', '紧凑', '只保留最关键的一行内容'),
  standard('standard', '标准', '展示两行内容，适合多数桌面尺寸'),
  detailed('detailed', '详细', '展示三行内容，适合大尺寸组件');

  final String id;
  final String label;
  final String description;

  const _WidgetDisplayMode(this.id, this.label, this.description);

  static _WidgetDisplayMode fromId(String? id) {
    return _WidgetDisplayMode.values.firstWhere(
      (mode) => mode.id == id,
      orElse: () => _WidgetDisplayMode.standard,
    );
  }
}

class _WidgetDisplayModePanel extends StatelessWidget {
  final _WidgetDisplayMode value;
  final ValueChanged<_WidgetDisplayMode> onChanged;

  const _WidgetDisplayModePanel({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppSurfaceCard(
      padding: const EdgeInsets.all(12),
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '小组件样式',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w400),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SegmentedButton<_WidgetDisplayMode>(
            segments: [
              for (final mode in _WidgetDisplayMode.values)
                ButtonSegment(value: mode, label: Text(mode.label)),
            ],
            selected: {value},
            showSelectedIcon: false,
            onSelectionChanged: (next) => onChanged(next.single),
          ),
          const SizedBox(height: 8),
          Text(
            value.description,
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _AddWidgetButton extends StatelessWidget {
  final DuoyiWidgetKind kind;

  const _AddWidgetButton({required this.kind});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: FilledButton.icon(
        onPressed: () => _request(context),
        icon: const Icon(Icons.add_to_home_screen_outlined),
        label: const Text('添加到桌面'),
      ),
    );
  }

  Future<void> _request(BuildContext context) async {
    final supported = await AndroidWidgetManager.canRequestPinWidget();
    if (supported) {
      final ok = await AndroidWidgetManager.requestPinWidget(kind);
      if (ok || !context.mounted) return;
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AppDialog(
        title: const Text('开启桌面小组件'),
        content: const Text('当前桌面不支持应用内直接添加，或系统未开放小组件创建权限。请到桌面/系统设置里开启后再添加。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await AndroidWidgetManager.openWidgetSettings();
            },
            child: const Text('去设置'),
          ),
        ],
      ),
    );
  }
}

class WidgetPreviewCard extends StatelessWidget {
  final WidgetPreviewKind kind;

  const WidgetPreviewCard.todo({super.key}) : kind = WidgetPreviewKind.todo;
  const WidgetPreviewCard.focus({super.key}) : kind = WidgetPreviewKind.focus;
  const WidgetPreviewCard.habit({super.key}) : kind = WidgetPreviewKind.habit;
  const WidgetPreviewCard.calendar({super.key})
    : kind = WidgetPreviewKind.calendar;
  const WidgetPreviewCard.schedule({super.key})
    : kind = WidgetPreviewKind.schedule;
  const WidgetPreviewCard.goal({super.key}) : kind = WidgetPreviewKind.goal;
  const WidgetPreviewCard.course({super.key}) : kind = WidgetPreviewKind.course;
  const WidgetPreviewCard.note({super.key}) : kind = WidgetPreviewKind.note;
  const WidgetPreviewCard.anniversary({super.key})
    : kind = WidgetPreviewKind.anniversary;
  const WidgetPreviewCard.diary({super.key}) : kind = WidgetPreviewKind.diary;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = switch (kind) {
      WidgetPreviewKind.todo => Colors.blue,
      WidgetPreviewKind.focus => Colors.redAccent,
      WidgetPreviewKind.habit => Colors.green,
      WidgetPreviewKind.calendar => Colors.indigo,
      WidgetPreviewKind.schedule => Colors.cyan,
      WidgetPreviewKind.goal => Colors.orange,
      WidgetPreviewKind.course => Colors.orange,
      WidgetPreviewKind.note => Colors.purple,
      WidgetPreviewKind.anniversary => Colors.pink,
      WidgetPreviewKind.diary => Colors.teal,
    };
    final title = switch (kind) {
      WidgetPreviewKind.todo => '今日待办预览',
      WidgetPreviewKind.focus => '专注预览',
      WidgetPreviewKind.habit => '习惯预览',
      WidgetPreviewKind.calendar => '月历预览',
      WidgetPreviewKind.schedule => '今日日程预览',
      WidgetPreviewKind.goal => '目标预览',
      WidgetPreviewKind.course => '课程表预览',
      WidgetPreviewKind.note => '随手记预览',
      WidgetPreviewKind.anniversary => '纪念日预览',
      WidgetPreviewKind.diary => '日记预览',
    };
    return Semantics(
      label: title,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.52),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.62)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  switch (kind) {
                    WidgetPreviewKind.todo => Icons.checklist_rtl_outlined,
                    WidgetPreviewKind.focus => Icons.timer_outlined,
                    WidgetPreviewKind.habit => Icons.self_improvement_outlined,
                    WidgetPreviewKind.calendar => Icons.calendar_month_outlined,
                    WidgetPreviewKind.schedule => Icons.event_note_outlined,
                    WidgetPreviewKind.goal => Icons.flag_outlined,
                    WidgetPreviewKind.course => Icons.school_outlined,
                    WidgetPreviewKind.note => Icons.edit_note_outlined,
                    WidgetPreviewKind.anniversary =>
                      Icons.event_available_outlined,
                    WidgetPreviewKind.diary => Icons.book_outlined,
                  },
                  size: 18,
                  color: accent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                Text(
                  '05/17',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 10),
            switch (kind) {
              WidgetPreviewKind.todo => const _WidgetPreviewTodoBody(),
              WidgetPreviewKind.focus => const _WidgetPreviewFocusBody(),
              WidgetPreviewKind.habit => const _WidgetPreviewHabitBody(),
              WidgetPreviewKind.calendar => const _WidgetPreviewCalendarBody(),
              WidgetPreviewKind.schedule => const _WidgetPreviewScheduleBody(),
              WidgetPreviewKind.goal => const _WidgetPreviewGoalBody(),
              WidgetPreviewKind.course => const _WidgetPreviewCourseBody(),
              WidgetPreviewKind.note => const _WidgetPreviewNoteBody(),
              WidgetPreviewKind.anniversary =>
                const _WidgetPreviewAnniversaryBody(),
              WidgetPreviewKind.diary => const _WidgetPreviewDiaryBody(),
            },
            const SizedBox(height: 10),
            _WidgetPreviewNav(
              selectedIndex: switch (kind) {
                WidgetPreviewKind.todo => 0,
                WidgetPreviewKind.focus => 3,
                WidgetPreviewKind.habit => 1,
                WidgetPreviewKind.calendar => 2,
                WidgetPreviewKind.schedule => 2,
                WidgetPreviewKind.goal => 2,
                WidgetPreviewKind.course => 2,
                WidgetPreviewKind.note => 2,
                WidgetPreviewKind.anniversary => 2,
                WidgetPreviewKind.diary => 2,
              },
              accent: accent,
            ),
          ],
        ),
      ),
    );
  }
}

enum WidgetPreviewKind {
  todo,
  focus,
  habit,
  calendar,
  schedule,
  goal,
  course,
  note,
  anniversary,
  diary,
}

class _WidgetPreviewTodoBody extends StatelessWidget {
  const _WidgetPreviewTodoBody();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _WidgetPreviewLine(
          icon: Icons.warning_amber_outlined,
          text: '逾期 1 项 · 20:25 有提醒 · 今日优先处理',
        ),
        const SizedBox(height: 5),
        const _WidgetPreviewTodoRow(text: '整理今日计划', checked: false),
        const SizedBox(height: 7),
        const _WidgetPreviewTodoRow(text: '完成项目复盘 · 3 个子任务', checked: false),
        const SizedBox(height: 7),
        const _WidgetPreviewTodoRow(text: '晚间运动 30 分钟', checked: true),
        const SizedBox(height: 6),
        const _WidgetPreviewQuickAdd(label: '+ 添加待办'),
        const SizedBox(height: 5),
        const _WidgetPreviewLine(
          icon: Icons.subdirectory_arrow_right,
          text: 'AI 子任务：列清单 / 订闹钟 / 完成确认 / 今日可见',
        ),
      ],
    );
  }
}

class _WidgetPreviewFocusBody extends StatelessWidget {
  const _WidgetPreviewFocusBody();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Row(
          children: [
            Expanded(
              child: _WidgetPreviewMetric(
                value: '2',
                label: '专注',
                color: Colors.redAccent,
              ),
            ),
            Expanded(
              child: _WidgetPreviewMetric(
                value: '50',
                label: '分钟',
                color: Colors.redAccent,
              ),
            ),
            Expanded(
              child: _WidgetPreviewMetric(
                value: '25',
                label: '下一轮',
                color: Colors.redAccent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Container(
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '开始 25 分钟专注',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const _WidgetPreviewLine(
          icon: Icons.timer_outlined,
          text: '今日专注 2 次 · 深度工作 50 分钟',
        ),
        const _WidgetPreviewLine(
          icon: Icons.play_circle_outline,
          text: '下一轮 25 分钟 · 点击立即开始',
        ),
        const _WidgetPreviewLine(
          icon: Icons.notifications_active_outlined,
          text: '结束后提醒休息 5 分钟',
        ),
      ],
    );
  }
}

class _WidgetPreviewHabitBody extends StatelessWidget {
  const _WidgetPreviewHabitBody();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _WidgetPreviewMetric(
                value: '4/5',
                label: '完成',
                color: Colors.green,
              ),
            ),
            Expanded(
              child: _WidgetPreviewMetric(
                value: '80%',
                label: '进度',
                color: Colors.green,
              ),
            ),
            Expanded(
              child: _WidgetPreviewMetric(
                value: '12',
                label: '连续',
                color: Colors.green,
              ),
            ),
          ],
        ),
        SizedBox(height: 8),
        _WidgetPreviewLine(
          icon: Icons.self_improvement_outlined,
          text: '晚间拉伸 · 今天待打卡',
        ),
        _WidgetPreviewLine(
          icon: Icons.water_drop_outlined,
          text: '喝水 · 已记录 7 杯',
        ),
        _WidgetPreviewLine(
          icon: Icons.local_fire_department_outlined,
          text: '连续记录 12 天',
        ),
      ],
    );
  }
}

class _WidgetPreviewCalendarBody extends StatelessWidget {
  const _WidgetPreviewCalendarBody();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '一 二 三 四 五 六 日\n          1  2  3\n 4  5  6  7  8  9 10\n11 12 13 14 15 16 17\n18 19 20 21 22 23 24\n25 26 27 28 29 30 31',
          style: TextStyle(
            fontSize: 11,
            height: 1.25,
            letterSpacing: 0,
            fontFamily: 'monospace',
            color: cs.onSurface,
          ),
        ),
      ],
    );
  }
}

class _WidgetPreviewScheduleBody extends StatelessWidget {
  const _WidgetPreviewScheduleBody();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _WidgetPreviewLine(
          icon: Icons.notifications_active_outlined,
          text: '20:25 厕所 · 到点提醒',
        ),
        _WidgetPreviewLine(icon: Icons.event_note_outlined, text: '14:30 团队例会'),
        _WidgetPreviewLine(
          icon: Icons.event_available_outlined,
          text: '19:00 晚间复盘',
        ),
      ],
    );
  }
}

class _WidgetPreviewGoalBody extends StatelessWidget {
  const _WidgetPreviewGoalBody();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _WidgetPreviewLine(icon: Icons.flag_outlined, text: '发版准备 · 68%'),
        _WidgetPreviewLine(
          icon: Icons.trending_up_outlined,
          text: '本周运动 3/5 次',
        ),
        _WidgetPreviewLine(
          icon: Icons.check_circle_outline,
          text: '晚间复盘 · 今日待推进',
        ),
      ],
    );
  }
}

class _WidgetPreviewCourseBody extends StatelessWidget {
  const _WidgetPreviewCourseBody();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _WidgetPreviewLine(
          icon: Icons.school_outlined,
          text: '第 1-2 节 高等数学 · 教 203',
        ),
        _WidgetPreviewLine(
          icon: Icons.school_outlined,
          text: '第 3-4 节 产品设计 · 线上',
        ),
        _WidgetPreviewLine(
          icon: Icons.event_note_outlined,
          text: '14:30 团队例会 · 打开日历查看',
        ),
      ],
    );
  }
}

class _WidgetPreviewNoteBody extends StatelessWidget {
  const _WidgetPreviewNoteBody();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _WidgetPreviewLine(icon: Icons.edit_note_outlined, text: '会议纪要'),
        _WidgetPreviewLine(icon: Icons.lightbulb_outline, text: '灵感清单'),
        _WidgetPreviewLine(icon: Icons.menu_book_outlined, text: '读书摘录'),
      ],
    );
  }
}

class _WidgetPreviewAnniversaryBody extends StatelessWidget {
  const _WidgetPreviewAnniversaryBody();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _WidgetPreviewLine(
          icon: Icons.event_available_outlined,
          text: '相识纪念日 · 还有 6 天',
        ),
        _WidgetPreviewLine(
          icon: Icons.event_available_outlined,
          text: '入职周年 · 还有 18 天',
        ),
        _WidgetPreviewLine(
          icon: Icons.event_available_outlined,
          text: '旅行纪念 · 还有 32 天',
        ),
      ],
    );
  }
}

class _WidgetPreviewDiaryBody extends StatelessWidget {
  const _WidgetPreviewDiaryBody();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _WidgetPreviewLine(icon: Icons.book_outlined, text: '5/18 今天完成了专注复盘'),
        _WidgetPreviewLine(icon: Icons.book_outlined, text: '5/17 记录一次散步'),
        _WidgetPreviewLine(icon: Icons.book_outlined, text: '5/16 睡前整理心情'),
      ],
    );
  }
}

class _WidgetPreviewQuickAdd extends StatelessWidget {
  final String label;

  const _WidgetPreviewQuickAdd({required this.label});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue.withValues(alpha: 0.28)),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.blue,
            fontSize: 11,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _WidgetPreviewLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _WidgetPreviewLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 13, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _WidgetPreviewTodoRow extends StatelessWidget {
  final String text;
  final bool checked;

  const _WidgetPreviewTodoRow({required this.text, required this.checked});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            '- $text',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: cs.onSurface),
          ),
        ),
        Icon(
          checked ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 16,
          color: checked ? Colors.green : cs.onSurfaceVariant,
        ),
      ],
    );
  }
}

class _WidgetPreviewMetric extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _WidgetPreviewMetric({
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w400,
            color: color,
          ),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _WidgetPreviewNav extends StatelessWidget {
  final int selectedIndex;
  final Color accent;

  const _WidgetPreviewNav({required this.selectedIndex, required this.accent});

  @override
  Widget build(BuildContext context) {
    const labels = ['待办', '习惯', '日历', '专注'];
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 30,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Center(
                child: Text(
                  labels[i],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: i == selectedIndex ? accent : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _WidgetCatalogTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  const _WidgetCatalogTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.14),
        child: Icon(icon, color: color),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
    );
  }
}
