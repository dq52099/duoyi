import 'package:flutter/material.dart';
import '../widgets/surface_components.dart';

class WidgetScreen extends StatelessWidget {
  const WidgetScreen({super.key});

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
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const _WidgetCatalogTile(
            icon: Icons.dashboard_customize_outlined,
            title: '多仪概览',
            subtitle: '今日待办数、习惯完成率、今日专注和日程摘要',
            color: Colors.teal,
          ),
          const SizedBox(height: 10),
          const WidgetPreviewCard.overview(),
          const SizedBox(height: 16),
          const _WidgetCatalogTile(
            icon: Icons.checklist_rtl_outlined,
            title: '今日待办',
            subtitle: '展示前三个今日任务，可从桌面直接进入任务',
            color: Colors.blue,
          ),
          const SizedBox(height: 10),
          const WidgetPreviewCard.todo(),
          const SizedBox(height: 12),
          AppInfoBanner(
            icon: Icons.touch_app_outlined,
            color: Colors.teal,
            message: '在系统桌面长按空白处，选择“小组件”，找到“多仪”后拖到桌面。',
          ),
        ],
      ),
    );
  }
}

class WidgetPreviewCard extends StatelessWidget {
  final bool todoOnly;

  const WidgetPreviewCard.overview({super.key}) : todoOnly = false;
  const WidgetPreviewCard.todo({super.key}) : todoOnly = true;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = todoOnly ? Colors.blue : Colors.teal;
    return Semantics(
      label: todoOnly ? '今日待办预览' : '多仪概览预览',
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
                  todoOnly
                      ? Icons.checklist_rtl_outlined
                      : Icons.dashboard_customize_outlined,
                  size: 18,
                  color: accent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    todoOnly ? '今日待办预览' : '多仪概览预览',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
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
            todoOnly
                ? const _WidgetPreviewTodoBody()
                : const _WidgetPreviewOverviewBody(),
            const SizedBox(height: 10),
            _WidgetPreviewNav(selectedIndex: todoOnly ? 0 : 2, accent: accent),
          ],
        ),
      ),
    );
  }
}

class _WidgetPreviewOverviewBody extends StatelessWidget {
  const _WidgetPreviewOverviewBody();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Row(
          children: [
            Expanded(
              child: _WidgetPreviewMetric(
                value: '3',
                label: '待办',
                color: Colors.blue,
              ),
            ),
            Expanded(
              child: _WidgetPreviewMetric(
                value: '80%',
                label: '习惯',
                color: Colors.green,
              ),
            ),
            Expanded(
              child: _WidgetPreviewMetric(
                value: '2',
                label: '专注',
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
                  color: Colors.teal,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '开始专注',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.teal),
                ),
                child: const Text(
                  '打开 App',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.teal, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '14:30 团队例会',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _WidgetPreviewTodoBody extends StatelessWidget {
  const _WidgetPreviewTodoBody();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _WidgetPreviewTodoRow(text: '整理今日计划', checked: false),
        SizedBox(height: 7),
        _WidgetPreviewTodoRow(text: '完成项目复盘', checked: false),
        SizedBox(height: 7),
        _WidgetPreviewTodoRow(text: '晚间运动 30 分钟', checked: true),
      ],
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
            fontWeight: FontWeight.w700,
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
                    fontWeight: i == selectedIndex
                        ? FontWeight.w700
                        : FontWeight.w500,
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
