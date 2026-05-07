import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_lock_provider.dart';

class LockSettingsScreen extends StatefulWidget {
  const LockSettingsScreen({super.key});

  @override
  State<LockSettingsScreen> createState() => _LockSettingsScreenState();
}

class _LockSettingsScreenState extends State<LockSettingsScreen> {
  Future<void> _setPinFlow() async {
    final pin = await _askPin('设置 PIN (4-8 位数字)');
    if (pin == null) return;
    final confirm = await _askPin('再输一遍确认');
    if (confirm == null) return;
    if (pin != confirm) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('两次输入不一致')));
      return;
    }
    final ok = await context.read<AppLockProvider>().setPin(pin);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '应用锁已启用' : 'PIN 长度需 4-8 位')),
    );
  }

  Future<void> _disableFlow() async {
    final pin = await _askPin('输入当前 PIN 以关闭');
    if (pin == null) return;
    final lock = context.read<AppLockProvider>();
    final ok = await lock.verify(pin);
    if (!ok) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PIN 错误')));
      return;
    }
    await lock.disable(pin);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('应用锁已关闭')));
  }

  Future<String?> _askPin(String title) async {
    final ctrl = TextEditingController();
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
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
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('确认')),
        ],
      ),
    );
    if (v == null) return null;
    if (v.length < 4 || v.length > 8) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('需要 4-8 位数字')));
      return null;
    }
    return v;
  }

  @override
  Widget build(BuildContext context) {
    final lock = context.watch<AppLockProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('应用锁')),
      body: ListView(
        children: [
          SwitchListTile(
            value: lock.enabled,
            title: const Text('启用应用锁'),
            subtitle: const Text('每次启动或切回前台时需要 PIN'),
            onChanged: (v) => v ? _setPinFlow() : _disableFlow(),
          ),
          if (lock.enabled) ...[
            ListTile(
              leading: const Icon(Icons.password),
              title: const Text('更换 PIN'),
              onTap: _setPinFlow,
            ),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('自动锁定'),
              subtitle: Text(lock.autoLockMinutes == 0
                  ? '每次切回前台都锁'
                  : '离开 ${lock.autoLockMinutes} 分钟后锁定'),
              trailing: DropdownButton<int>(
                value: lock.autoLockMinutes,
                underline: const SizedBox(),
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
            ListTile(
              leading: const Icon(Icons.lock_outline, color: Colors.red),
              title: const Text('立即锁定', style: TextStyle(color: Colors.red)),
              onTap: () {
                context.read<AppLockProvider>().lock();
                Navigator.pop(context);
              },
            ),
          ],
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '提示：应用锁仅作用于本机，云端数据不受影响；忘记 PIN 只能清应用数据找回。',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}
