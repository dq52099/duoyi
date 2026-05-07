import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/app_lock_provider.dart';
import '../providers/theme_provider.dart';

/// PIN 解锁页：作为全屏覆盖层挡在主界面之上。
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String _input = '';
  String? _error;
  bool _busy = false;

  Future<void> _press(String k) async {
    if (_busy) return;
    setState(() {
      _error = null;
      if (k == 'del') {
        if (_input.isNotEmpty) _input = _input.substring(0, _input.length - 1);
      } else if (_input.length < 8) {
        _input += k;
      }
    });
    if (_input.length >= 4) {
      final lock = context.read<AppLockProvider>();
      setState(() => _busy = true);
      final ok = await lock.verify(_input);
      if (!mounted) return;
      if (ok) {
        await lock.unlockWith(_input);
        HapticFeedback.lightImpact();
      } else {
        HapticFeedback.heavyImpact();
        setState(() {
          _error = 'PIN 错误';
          _input = '';
        });
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<ThemeProvider>().brand.strings;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            Icon(Icons.lock, size: 48, color: cs.primary),
            const SizedBox(height: 10),
            Text(s.appTitle,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            const Text('输入 PIN 解锁',
                style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _input.length.clamp(0, 8),
                (i) => Container(
                  width: 12,
                  height: 12,
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    color: cs.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_error!,
                    style: const TextStyle(color: Colors.red)),
              ),
            const Spacer(),
            _Keypad(onTap: _press),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  final void Function(String) onTap;
  const _Keypad({required this.onTap});

  @override
  Widget build(BuildContext context) {
    Widget btn(String v, {Widget? child}) => Expanded(
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: InkResponse(
              onTap: () => onTap(v),
              radius: 40,
              child: Container(
                height: 56,
                alignment: Alignment.center,
                child: child ??
                    Text(v,
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w500)),
              ),
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36),
      child: Column(
        children: [
          Row(children: [btn('1'), btn('2'), btn('3')]),
          Row(children: [btn('4'), btn('5'), btn('6')]),
          Row(children: [btn('7'), btn('8'), btn('9')]),
          Row(children: [
            const Expanded(child: SizedBox()),
            btn('0'),
            btn('del', child: const Icon(Icons.backspace_outlined)),
          ]),
        ],
      ),
    );
  }
}
