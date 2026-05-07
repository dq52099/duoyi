import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/preferences_provider.dart';

/// 偏好设置页。纯本地的用户习惯，与服务器/管理员配置无关。
class PreferencesScreen extends StatelessWidget {
  const PreferencesScreen({super.key});

  static const _dateFormats = [
    ['yyyy-MM-dd', '2026-05-07'],
    ['MM/dd/yyyy', '05/07/2026'],
    ['dd/MM/yyyy', '07/05/2026'],
    ['yyyy年M月d日', '2026年5月7日'],
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PreferencesProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('偏好设置')),
      body: ListView(
        children: [
          _section('日期与日历'),
          ListTile(
            title: const Text('一周从哪一天开始'),
            trailing: DropdownButton<int>(
              value: p.firstDayOfWeek,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: 1, child: Text('周一')),
                DropdownMenuItem(value: 7, child: Text('周日')),
              ],
              onChanged: (v) =>
                  v == null ? null : context.read<PreferencesProvider>().setFirstDayOfWeek(v),
            ),
          ),
          ListTile(
            title: const Text('日期格式'),
            trailing: DropdownButton<String>(
              value: p.dateFormat,
              underline: const SizedBox(),
              items: [
                for (final f in _dateFormats)
                  DropdownMenuItem(
                    value: f[0],
                    child: Text(f[1], style: const TextStyle(fontSize: 13)),
                  ),
              ],
              onChanged: (v) =>
                  v == null ? null : context.read<PreferencesProvider>().setDateFormat(v),
            ),
          ),
          SwitchListTile(
            value: p.showLunar,
            title: const Text('显示农历'),
            subtitle: const Text('影响日历月视图与今日卡'),
            onChanged: (v) =>
                context.read<PreferencesProvider>().setShowLunar(v),
          ),
          _section('默认行为'),
          ListTile(
            title: const Text('启动默认 Tab'),
            trailing: DropdownButton<int>(
              value: p.defaultTab,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: 0, child: Text('今日')),
                DropdownMenuItem(value: 1, child: Text('待办')),
                DropdownMenuItem(value: 2, child: Text('习惯')),
                DropdownMenuItem(value: 3, child: Text('日历')),
                DropdownMenuItem(value: 4, child: Text('专注')),
                DropdownMenuItem(value: 5, child: Text('我的')),
              ],
              onChanged: (v) =>
                  v == null ? null : context.read<PreferencesProvider>().setDefaultTab(v),
            ),
          ),
          SwitchListTile(
            value: p.quickCaptureFab,
            title: const Text('显示快速捕获按钮'),
            subtitle: const Text('今日 / 我的 页右下角的 + 按钮'),
            onChanged: (v) =>
                context.read<PreferencesProvider>().setQuickCaptureFab(v),
          ),
          SwitchListTile(
            value: p.showCompletedTodos,
            title: const Text('待办页显示已完成'),
            onChanged: (v) =>
                context.read<PreferencesProvider>().setShowCompletedTodos(v),
          ),
          ListTile(
            title: const Text('默认番茄钟长度'),
            subtitle: Text('${p.defaultPomodoroMinutes} 分钟'),
            trailing: SizedBox(
              width: 160,
              child: Slider(
                value: p.defaultPomodoroMinutes.toDouble(),
                min: 5,
                max: 90,
                divisions: 17,
                label: '${p.defaultPomodoroMinutes} 分',
                onChanged: (v) => context
                    .read<PreferencesProvider>()
                    .setDefaultPomodoroMinutes(v.toInt()),
              ),
            ),
          ),
          _section('交互'),
          SwitchListTile(
            value: p.haptic,
            title: const Text('震动反馈'),
            subtitle: const Text('完成/切换/解锁等操作'),
            onChanged: (v) =>
                context.read<PreferencesProvider>().setHaptic(v),
          ),
          _section('待办自动归档'),
          ListTile(
            title: const Text('完成 N 天后隐藏'),
            subtitle: Text(p.autoArchiveCompletedDays == 0
                ? '从不归档'
                : '${p.autoArchiveCompletedDays} 天后自动隐藏'),
            trailing: SizedBox(
              width: 160,
              child: Slider(
                value: p.autoArchiveCompletedDays.toDouble(),
                min: 0,
                max: 30,
                divisions: 30,
                label: p.autoArchiveCompletedDays == 0
                    ? '关'
                    : '${p.autoArchiveCompletedDays} 天',
                onChanged: (v) => context
                    .read<PreferencesProvider>()
                    .setAutoArchiveCompletedDays(v.toInt()),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade600,
          ),
        ),
      );
}
