import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../services/api_client.dart';
import '../widgets/brand_background.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _userCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  final _inviteCtrl = TextEditingController();
  final _serverCtrl = TextEditingController();
  bool _isRegister = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _serverCtrl.text = context.read<AuthProvider>().baseUrl;
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _pwdCtrl.dispose();
    _inviteCtrl.dispose();
    _serverCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = context.read<AuthProvider>();
    try {
      if (_serverCtrl.text.trim() != auth.baseUrl) {
        await auth.setBaseUrl(_serverCtrl.text.trim());
      }
      if (_isRegister) {
        await auth.register(
          username: _userCtrl.text.trim(),
          password: _pwdCtrl.text,
          inviteCode: auth.inviteCodeRequired ? _inviteCtrl.text.trim() : null,
        );
      } else {
        await auth.login(username: _userCtrl.text.trim(), password: _pwdCtrl.text);
      }
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<ThemeProvider>().brand.strings;
    final auth = context.watch<AuthProvider>();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: Text(_isRegister ? '注册账号' : '登录'), backgroundColor: Colors.transparent),
      body: BrandBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          children: [
            const SizedBox(height: 12),
            Text(s.appTitle, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: cs.primary)),
            const SizedBox(height: 8),
            Text(_isRegister ? '创建一个账号开启多端同步' : '使用账号登录享受云同步与公告',
                style: TextStyle(color: cs.onSurface.withValues(alpha: 0.7))),
            const SizedBox(height: 24),
            TextField(
              controller: _serverCtrl,
              decoration: const InputDecoration(labelText: '服务器地址', hintText: 'http://your-server:8000'),
            ),
            const SizedBox(height: 12),
            TextField(controller: _userCtrl, decoration: const InputDecoration(labelText: '用户名')),
            const SizedBox(height: 12),
            TextField(
              controller: _pwdCtrl,
              decoration: const InputDecoration(labelText: '密码'),
              obscureText: true,
            ),
            if (_isRegister && auth.inviteCodeRequired) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _inviteCtrl,
                decoration: const InputDecoration(labelText: '邀请码'),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_isRegister ? '注册' : '登录'),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => setState(() => _isRegister = !_isRegister),
              child: Text(_isRegister ? '已有账号？去登录' : '没有账号？去注册'),
            ),
          ],
        ),
      ),
    );
  }
}
