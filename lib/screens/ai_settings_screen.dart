import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/ai_service.dart';

class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
  final _baseCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final ai = context.read<AiService>();
    _baseCtrl.text = ai.baseUrl;
    _keyCtrl.text = ai.apiKey;
    _modelCtrl.text = ai.model;
  }

  @override
  void dispose() {
    _baseCtrl.dispose();
    _keyCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await context.read<AiService>().configure(
      baseUrl: _baseCtrl.text,
      apiKey: _keyCtrl.text,
      model: _modelCtrl.text,
    );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('AI 配置已保存')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ai = context.watch<AiService>();
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('AI 助手'),
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            value: ai.enabled,
            title: const Text('启用 AI 助手'),
            subtitle: const Text('开启后在新建任务和我的页可使用 AI 功能'),
            onChanged: (v) => context.read<AiService>().configure(enabled: v),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _baseCtrl,
            decoration: const InputDecoration(
              labelText: 'Base URL',
              hintText: 'https://image.6688667.xyz',
              helperText: 'OpenAI 兼容 API 网关，路径后会自动加 /v1/chat/completions',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _keyCtrl,
            decoration: const InputDecoration(labelText: 'API Key'),
            obscureText: true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _modelCtrl,
            decoration: const InputDecoration(
              labelText: '模型',
              hintText: 'gpt-4o-mini / claude-3-haiku-20240307 等',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: const Text('保存')),
          const Divider(height: 32),
          const Text('AI 能做什么', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          const ListTile(
            dense: true,
            leading: Icon(Icons.auto_awesome, size: 18),
            title: Text('AI 任务拆解 — 在新建待办时一键将一句话拆为子任务'),
          ),
          const ListTile(
            dense: true,
            leading: Icon(Icons.summarize_outlined, size: 18),
            title: Text('AI 每周回顾 — 在我的页根据本周数据生成总结与建议'),
          ),
        ],
      ),
    );
  }
}
