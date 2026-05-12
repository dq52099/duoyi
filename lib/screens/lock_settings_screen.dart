import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_lock_provider.dart';
import '../widgets/surface_components.dart';

class LockSettingsScreen extends StatefulWidget {
  const LockSettingsScreen({super.key});

  @override
  State<LockSettingsScreen> createState() => _LockSettingsScreenState();
}

class _LockSettingsScreenState extends State<LockSettingsScreen> {
  Future<void> _setPinFlow() async {
    final messenger = ScaffoldMessenger.of(context);
    final lock = context.read<AppLockProvider>();
    final pin = await _askPin('设置 PIN (4-8 位数字)');
    if (pin == null) return;
    final confirm = await _askPin('再输一遍确认');
    if (confirm == null) return;
    if (pin != confirm) {
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('两次输入不一致')));
      return;
    }
    final ok = await lock.setPin(pin);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text(ok ? '应用锁已启用' : 'PIN 长度需 4-8 位')),
    );
  }

  Future<void> _disableFlow() async {
    final messenger = ScaffoldMessenger.of(context);
    final lock = context.read<AppLockProvider>();
    final pin = await _askPin('输入当前 PIN 以关闭');
    if (pin == null) return;
    final ok = await lock.verify(pin);
    if (!ok) {
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('PIN 错误')));
      return;
    }
    await lock.disable(pin);
    if (!mounted) return;
    messenger.showSnackBar(const SnackBar(content: Text('应用锁已关闭')));
  }

  Future<String?> _askPin(String title) async {
    final ctrl = TextEditingController();
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AppDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 8,
          decoration: const InputDecoration(
            hintText: '4-8 位数字',
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (v == null) return null;
    if (v.length < 4 || v.length > 8) {
      if (!mounted) return null;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('需要 4-8 位数字')));
      return null;
    }
    return v;
  }

  @override
  Widget build(BuildContext context) {
    final lock = context.watch<AppLockProvider>();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('应用锁')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        children: [
          AppSurfaceCard(
            padding: const EdgeInsets.all(16),
            gradient: LinearGradient(
              colors: [cs.primary.withValues(alpha: 0.12), cs.surface],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.lock_outline, color: cs.primary, size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '本机 PIN 锁',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: cs.onSurface,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '用于保护本地数据，切回应用或重新启动时需要验证',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.66),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppSettingsSection(
            title: '锁定状态',
            subtitle: '启用后会在启动或切回前台时要求 PIN',
            children: [
              AppSwitchTile(
                icon: lock.enabled ? Icons.lock : Icons.lock_open,
                color: lock.enabled ? Colors.green : Colors.orange,
                title: '启用应用锁',
                subtitle: lock.enabled ? '当前已启用' : '关闭后不会再要求 PIN',
                value: lock.enabled,
                onChanged: (enabled) =>
                    enabled ? _setPinFlow() : _disableFlow(),
              ),
              if (lock.enabled) ...[
                AppSettingsTile(
                  icon: Icons.password,
                  color: cs.primary,
                  title: '更换 PIN',
                  subtitle: '重新设置 4-8 位数字密码',
                  onTap: _setPinFlow,
                ),
                AppSettingsTile(
                  icon: Icons.timer_outlined,
                  color: Colors.orange,
                  title: '自动锁定',
                  subtitle: lock.autoLockMinutes == 0
                      ? '每次切回前台都锁定'
                      : '离开 ${lock.autoLockMinutes} 分钟后锁定',
                  trailing: AppCompactDropdown<int>(
                    width: 132,
                    value: lock.autoLockMinutes,
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('立即')),
                      DropdownMenuItem(value: 1, child: Text('1 分钟')),
                      DropdownMenuItem(value: 5, child: Text('5 分钟')),
                      DropdownMenuItem(value: 15, child: Text('15 分钟')),
                      DropdownMenuItem(value: 60, child: Text('1 小时')),
                      DropdownMenuItem(value: 240, child: Text('4 小时')),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        context.read<AppLockProvider>().setAutoLockMinutes(v);
                      }
                    },
                  ),
                ),
                AppSettingsTile(
                  icon: Icons.lock_clock_outlined,
                  color: Colors.red,
                  title: '立即锁定',
                  subtitle: '立刻切回输入 PIN',
                  onTap: () {
                    context.read<AppLockProvider>().lock();
                    Navigator.pop(context);
                  },
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          AppSurfaceCard(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: cs.primary, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '提示：应用锁仅作用于本机，云端数据不受影响；忘记 PIN 只能清应用数据找回。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.68),
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
