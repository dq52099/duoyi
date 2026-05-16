import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/app_config.dart';
import '../providers/auth_provider.dart';
import '../services/admin_api.dart';
import '../services/api_client.dart';
import '../widgets/empty_state.dart';
import '../widgets/surface_components.dart';

/// 管理员后台 — 仅当 AuthProvider.state.isAdmin == true 时可进入。
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 8, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (!auth.state.isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('管理员后台')),
        body: const EmptyState(icon: Icons.lock, message: '仅管理员可访问'),
      );
    }
    final api = AdminApi(auth.client);

    return Scaffold(
      appBar: AppBar(
        title: const Text('管理员后台'),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          labelPadding: const EdgeInsets.symmetric(horizontal: 6),
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          indicator: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          labelColor: Theme.of(context).colorScheme.onPrimaryContainer,
          unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
          tabs: const [
            Tab(
              height: 44,
              child: _AdminTabLabel(icon: Icons.dashboard_outlined, text: '概览'),
            ),
            Tab(
              height: 44,
              child: _AdminTabLabel(icon: Icons.tune, text: '全站设置'),
            ),
            Tab(
              height: 44,
              child: _AdminTabLabel(icon: Icons.auto_awesome, text: 'AI 配置'),
            ),
            Tab(
              height: 44,
              child: _AdminTabLabel(icon: Icons.cloud_outlined, text: '云端备份'),
            ),
            Tab(
              height: 44,
              child: _AdminTabLabel(icon: Icons.people_outline, text: '用户'),
            ),
            Tab(
              height: 44,
              child: _AdminTabLabel(icon: Icons.campaign_outlined, text: '公告'),
            ),
            Tab(
              height: 44,
              child: _AdminTabLabel(icon: Icons.feedback_outlined, text: '反馈'),
            ),
            Tab(
              height: 44,
              child: _AdminTabLabel(icon: Icons.vpn_key_outlined, text: '邀请码'),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _DashboardTab(api: api),
          _SettingsTab(api: api),
          _AiSettingsTab(api: api),
          _BackupSettingsTab(api: api),
          _UsersTab(api: api, selfId: auth.state.userId),
          _AnnouncementsTab(api: api),
          _FeedbackTab(api: api),
          _InvitesTab(api: api),
        ],
      ),
    );
  }
}

class _AdminTabLabel extends StatelessWidget {
  final IconData icon;
  final String text;

  const _AdminTabLabel({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 92,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 6),
          Flexible(
            child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

// ====================================================================
// 概览
// ====================================================================

class _DashboardTab extends StatefulWidget {
  final AdminApi api;
  const _DashboardTab({required this.api});
  @override
  State<_DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<_DashboardTab> {
  Map<String, dynamic>? _stats;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _stats = await widget.api.stats();
    } on ApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_stats == null) {
      return Center(child: Text(_error ?? '加载失败'));
    }
    final users = _stats!['users'] as Map? ?? {};
    final fb = _stats!['feedback'] as Map? ?? {};
    final ann = _stats!['announcements'] as Map? ?? {};
    final inv = _stats!['invites'] as Map? ?? {};
    final series = (_stats!['registration_series'] as List?)?.cast<Map>() ?? [];
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          AppInfoBanner(
            icon: Icons.verified_outlined,
            color: Colors.indigo,
            title: '客户端连接',
            message: AppConfig.bakedServerUrl.isEmpty
                ? '相对路径 (同域反代)'
                : AppConfig.bakedServerUrl,
            margin: const EdgeInsets.only(bottom: 12),
          ),
          _GridCards([
            _Kpi('总用户', '${users['total'] ?? 0}', Icons.people, Colors.blue),
            _Kpi(
              '管理员',
              '${users['admin'] ?? 0}',
              Icons.shield,
              Colors.deepOrange,
            ),
            _Kpi('已禁用', '${users['disabled'] ?? 0}', Icons.block, Colors.red),
            _Kpi(
              '今日新增',
              '${users['new_today'] ?? 0}',
              Icons.person_add_alt,
              Colors.green,
            ),
            _Kpi(
              '7 日活跃',
              '${users['active_7d'] ?? 0}',
              Icons.trending_up,
              Colors.teal,
            ),
            _Kpi(
              '在线',
              '${_stats!['tokens_online'] ?? 0}',
              Icons.wifi_tethering,
              Colors.cyan,
            ),
            _Kpi(
              '待处理反馈',
              '${fb['open'] ?? 0}',
              Icons.chat_bubble_outline,
              Colors.orange,
            ),
            _Kpi(
              '反馈总数',
              '${fb['total'] ?? 0}',
              Icons.forum_outlined,
              Colors.grey,
            ),
            _Kpi(
              '公告(已发)',
              '${ann['published'] ?? 0}',
              Icons.campaign,
              Colors.indigo,
            ),
            _Kpi(
              '邀请码已用',
              '${inv['used'] ?? 0} / ${inv['total'] ?? 0}',
              Icons.vpn_key,
              Colors.purple,
            ),
          ]),
          const SizedBox(height: 14),
          AppSurfaceCard(
            padding: const EdgeInsets.all(14),
            child: Padding(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '近 7 天注册',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (series.isEmpty)
                    Text(
                      '暂无注册',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.58),
                      ),
                    ),
                  ...series.map((row) {
                    final count = ((row['count'] as num?) ?? 0).toDouble();
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 90,
                            child: Text(
                              row['date'].toString(),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurface.withValues(alpha: 0.68),
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: (count / 10).clamp(0.0, 1.0),
                                minHeight: 8,
                                backgroundColor: cs.surfaceContainerHighest,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${row['count']}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurface,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Kpi {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  const _Kpi(this.title, this.value, this.icon, this.color);
}

class _GridCards extends StatelessWidget {
  final List<_Kpi> items;
  const _GridCards(this.items);
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = Theme.of(context).colorScheme;
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      childAspectRatio: 2.4,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: items
          .map(
            (k) => AppSurfaceCard(
              padding: const EdgeInsets.all(12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: k.color.withValues(alpha: 0.16)),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: k.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(k.icon, color: k.color, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          k.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurface.withValues(alpha: 0.62),
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        Text(
                          k.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

// ====================================================================
// 全站设置
// ====================================================================

class _SettingsTab extends StatefulWidget {
  final AdminApi api;
  const _SettingsTab({required this.api});
  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  Map<String, dynamic> _data = {};
  bool _loading = true;
  bool _saving = false;
  String? _error;
  final _msgCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _data = await widget.api.getSettings();
      _msgCtrl.text = (_data['maintenance_message'] ?? '').toString();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _set(String key, dynamic value) async {
    setState(() => _saving = true);
    try {
      await widget.api.updateSettings(
        inviteCodeRequired: key == 'invite_code_required' ? value : null,
        registrationEnabled: key == 'registration_enabled' ? value : null,
        maintenanceMode: key == 'maintenance_mode' ? value : null,
        maintenanceMessage: key == 'maintenance_message' ? value : null,
      );
      _data[key] = value;
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    final cs = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AppSettingsSection(
          title: '账户与注册',
          subtitle: '控制新用户入口与邀请码策略',
          children: [
            AppSwitchTile(
              icon: Icons.person_add_alt_1_outlined,
              color: Colors.green,
              value: _data['registration_enabled'] == true,
              title: '允许注册',
              subtitle: '关闭后新用户无法注册，现有用户仍可登录',
              onChanged: _saving
                  ? null
                  : (v) => _set('registration_enabled', v),
            ),
            AppSwitchTile(
              icon: Icons.vpn_key_outlined,
              color: Colors.purple,
              value: _data['invite_code_required'] == true,
              title: '注册需要邀请码',
              subtitle: '只有带邀请码才能注册',
              onChanged: _saving
                  ? null
                  : (v) => _set('invite_code_required', v),
            ),
          ],
        ),
        const SizedBox(height: 12),
        AppSettingsSection(
          title: '维护模式',
          subtitle: '控制同步服务与客户端提示',
          children: [
            AppSwitchTile(
              icon: Icons.construction_outlined,
              color: Colors.orange,
              value: _data['maintenance_mode'] == true,
              title: '启用维护模式',
              subtitle: '开启后 /api/sync 拒绝服务；客户端登录页会提示',
              onChanged: _saving ? null : (v) => _set('maintenance_mode', v),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _msgCtrl,
              decoration: const InputDecoration(
                labelText: '维护公告文字',
                hintText: '将在客户端登录/同步报错时展示',
                prefixIcon: Icon(Icons.campaign_outlined),
              ),
              onEditingComplete: () =>
                  _set('maintenance_message', _msgCtrl.text.trim()),
            ),
          ],
        ),
        const SizedBox(height: 12),
        AppInfoBanner(
          icon: Icons.info_outline,
          color: cs.primary,
          title: '服务器地址',
          message: '服务器地址在 APK / Web 构建时就已锁定，运行期不可修改。如需切换后端，请重新构建并分发新版本。',
        ),
      ],
    );
  }
}

// ====================================================================
// AI 配置
// ====================================================================

class _AiSettingsTab extends StatefulWidget {
  final AdminApi api;
  const _AiSettingsTab({required this.api});
  @override
  State<_AiSettingsTab> createState() => _AiSettingsTabState();
}

class _AiSettingsTabState extends State<_AiSettingsTab> {
  bool _loading = true;
  bool _saving = false;
  bool _testing = false;
  String? _testResult;
  Color _testColor = Colors.grey;
  String? _error;
  bool _enabled = false;
  final _baseCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _quotaCtrl = TextEditingController(text: '0');
  bool _keyMasked = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _baseCtrl.dispose();
    _keyCtrl.dispose();
    _modelCtrl.dispose();
    _quotaCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.api.getSettings();
      _enabled = data['ai_enabled'] == true;
      _baseCtrl.text = (data['ai_base_url'] ?? '').toString();
      _keyCtrl.text = (data['ai_api_key'] ?? '').toString();
      _keyMasked = (data['ai_api_key_set'] == true);
      _modelCtrl.text = (data['ai_model'] ?? '').toString();
      _quotaCtrl.text = (((data['ai_daily_quota'] as num?) ?? 0).toInt())
          .toString();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final newKey = _keyCtrl.text.trim();
      final submitKey = (_keyMasked && newKey.contains('***')) ? null : newKey;
      final payload = <String, Object?>{
        'ai_enabled': _enabled,
        'ai_base_url': _baseCtrl.text.trim(),
        'ai_model': _modelCtrl.text.trim(),
        'ai_daily_quota': int.tryParse(_quotaCtrl.text.trim()) ?? 0,
      };
      if (submitKey != null) {
        payload['ai_api_key'] = submitKey;
      }
      await widget.api.client.patch('/api/admin/settings', payload);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('AI 配置已保存')));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final res = await widget.api.testAi();
      setState(() {
        _testResult = '✅ 模型 ${res['model']} 可达，回复: ${res['sample']}';
        _testColor = Colors.green;
      });
    } on ApiException catch (e) {
      setState(() {
        _testResult = '❌ ${e.message}';
        _testColor = Colors.red;
      });
    } catch (e) {
      setState(() {
        _testResult = '❌ $e';
        _testColor = Colors.red;
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AppSettingsSection(
          title: 'AI 功能',
          subtitle: '所有请求经后端代理，前端不暴露密钥',
          children: [
            AppSwitchTile(
              icon: Icons.auto_awesome,
              color: cs.primary,
              value: _enabled,
              title: '启用 AI 功能',
              subtitle: '关闭后所有用户都无法使用 AI 拆解/回顾',
              onChanged: (v) => setState(() => _enabled = v),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _baseCtrl,
              decoration: const InputDecoration(
                labelText: 'Base URL (OpenAI 兼容网关)',
                hintText: 'https://api.openai.com',
                helperText: '路径后自动加 /v1/chat/completions',
                prefixIcon: Icon(Icons.link_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _keyCtrl,
              decoration: InputDecoration(
                labelText: 'API Key',
                helperText: _keyMasked ? '已配置（显示为掩码，保持不动即不修改）' : '尚未配置',
                prefixIcon: const Icon(Icons.key_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _modelCtrl,
              decoration: const InputDecoration(
                labelText: '模型名称',
                hintText: 'gpt-4o-mini / claude-3-haiku-20240307',
                prefixIcon: Icon(Icons.memory_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _quotaCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '每用户每日调用上限',
                helperText: '0 = 不限',
                prefixIcon: Icon(Icons.speed_outlined),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_saving ? '保存中…' : '保存'),
                ),
                OutlinedButton.icon(
                  icon: _testing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.network_check),
                  label: const Text('测试连接'),
                  onPressed: _testing ? null : _test,
                ),
              ],
            ),
            if (_testResult != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _testColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _testColor.withValues(alpha: 0.18)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _testColor == Colors.green
                          ? Icons.check_circle_outline
                          : Icons.error_outline,
                      color: _testColor,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _testResult!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.74),
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        AppInfoBanner(
          icon: Icons.security_outlined,
          color: Colors.teal,
          title: '安全代理',
          message: '所有用户的 AI 请求都通过后端 /api/ai/chat 代理，前端永远拿不到 API Key。',
        ),
      ],
    );
  }
}

// ====================================================================
// 云端备份
// ====================================================================

class _BackupSettingsTab extends StatefulWidget {
  final AdminApi api;
  const _BackupSettingsTab({required this.api});
  @override
  State<_BackupSettingsTab> createState() => _BackupSettingsTabState();
}

class _BackupSettingsTabState extends State<_BackupSettingsTab> {
  bool _loading = true;
  bool _saving = false;
  bool _runningServerBackup = false;
  String? _error;

  bool _backupEnabled = true;
  bool _serverBackupEnabled = true;
  bool _openlistEnabled = false;
  bool _backupEmailEnabled = false;
  final _maxSizeCtrl = TextEditingController(text: '2048');
  final _intervalCtrl = TextEditingController(text: '30');
  final _retainCtrl = TextEditingController(text: '0');
  final _serverIntervalCtrl = TextEditingController(text: '720');
  final _serverRetainCtrl = TextEditingController(text: '14');
  final _openlistUrlCtrl = TextEditingController();
  final _openlistPublicUrlCtrl = TextEditingController();
  final _openlistUserCtrl = TextEditingController();
  final _openlistPasswordCtrl = TextEditingController();
  final _openlistPathCtrl = TextEditingController(text: '/duoyi-backups');
  final _emailToCtrl = TextEditingController();
  final _emailFromCtrl = TextEditingController();
  final _smtpHostCtrl = TextEditingController();
  final _smtpPortCtrl = TextEditingController(text: '465');
  final _smtpUserCtrl = TextEditingController();
  final _smtpPasswordCtrl = TextEditingController();
  bool _openlistPasswordMasked = false;
  bool _smtpPasswordMasked = false;

  List<Map<String, dynamic>> _backups = [];
  List<Map<String, dynamic>> _serverBackups = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _maxSizeCtrl.dispose();
    _intervalCtrl.dispose();
    _retainCtrl.dispose();
    _serverIntervalCtrl.dispose();
    _serverRetainCtrl.dispose();
    _openlistUrlCtrl.dispose();
    _openlistPublicUrlCtrl.dispose();
    _openlistUserCtrl.dispose();
    _openlistPasswordCtrl.dispose();
    _openlistPathCtrl.dispose();
    _emailToCtrl.dispose();
    _emailFromCtrl.dispose();
    _smtpHostCtrl.dispose();
    _smtpPortCtrl.dispose();
    _smtpUserCtrl.dispose();
    _smtpPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.api.getSettings();
      _backupEnabled = data['backup_enabled'] != false;
      _maxSizeCtrl.text =
          (((data['backup_max_size_kb'] as num?) ?? 2048).toInt()).toString();
      _intervalCtrl.text =
          (((data['backup_interval_minutes'] as num?) ?? 30).toInt())
              .toString();
      _retainCtrl.text = (((data['backup_retain_days'] as num?) ?? 0).toInt())
          .toString();
      _serverBackupEnabled = data['server_backup_enabled'] != false;
      _serverIntervalCtrl.text =
          (((data['server_backup_interval_minutes'] as num?) ?? 720).toInt())
              .toString();
      _serverRetainCtrl.text =
          (((data['server_backup_retain_days'] as num?) ?? 14).toInt())
              .toString();
      _openlistEnabled = data['openlist_backup_enabled'] == true;
      _openlistUrlCtrl.text = (data['openlist_webdav_url'] ?? '').toString();
      _openlistPublicUrlCtrl.text = (data['openlist_public_url'] ?? '')
          .toString();
      _openlistUserCtrl.text = (data['openlist_username'] ?? '').toString();
      _openlistPasswordCtrl.text = (data['openlist_password'] ?? '').toString();
      _openlistPasswordMasked = data['openlist_password_set'] == true;
      _openlistPathCtrl.text =
          (data['openlist_backup_path'] ?? '/duoyi-backups').toString();
      _backupEmailEnabled = data['backup_email_enabled'] == true;
      _emailToCtrl.text = (data['backup_email_to'] ?? '').toString();
      _emailFromCtrl.text = (data['backup_email_from'] ?? '').toString();
      _smtpHostCtrl.text = (data['backup_email_smtp_host'] ?? '').toString();
      _smtpPortCtrl.text =
          (((data['backup_email_smtp_port'] as num?) ?? 465).toInt())
              .toString();
      _smtpUserCtrl.text = (data['backup_email_smtp_username'] ?? '')
          .toString();
      _smtpPasswordCtrl.text = (data['backup_email_smtp_password'] ?? '')
          .toString();
      _smtpPasswordMasked = data['backup_email_smtp_password_set'] == true;
      _backups = await widget.api.listBackups();
      _serverBackups = await widget.api.listServerBackups();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final openlistPassword = _openlistPasswordCtrl.text.trim();
      final smtpPassword = _smtpPasswordCtrl.text.trim();
      final payload = <String, Object?>{
        'backup_enabled': _backupEnabled,
        'backup_max_size_kb': int.tryParse(_maxSizeCtrl.text.trim()) ?? 2048,
        'backup_interval_minutes':
            int.tryParse(_intervalCtrl.text.trim()) ?? 30,
        'backup_retain_days': int.tryParse(_retainCtrl.text.trim()) ?? 0,
        'server_backup_enabled': _serverBackupEnabled,
        'server_backup_interval_minutes':
            int.tryParse(_serverIntervalCtrl.text.trim()) ?? 720,
        'server_backup_retain_days':
            int.tryParse(_serverRetainCtrl.text.trim()) ?? 14,
        'openlist_backup_enabled': _openlistEnabled,
        'openlist_webdav_url': _openlistUrlCtrl.text.trim(),
        'openlist_public_url': _openlistPublicUrlCtrl.text.trim(),
        'openlist_username': _openlistUserCtrl.text.trim(),
        'openlist_backup_path': _openlistPathCtrl.text.trim(),
        'backup_email_enabled': _backupEmailEnabled,
        'backup_email_to': _emailToCtrl.text.trim(),
        'backup_email_from': _emailFromCtrl.text.trim(),
        'backup_email_smtp_host': _smtpHostCtrl.text.trim(),
        'backup_email_smtp_port':
            int.tryParse(_smtpPortCtrl.text.trim()) ?? 465,
        'backup_email_smtp_username': _smtpUserCtrl.text.trim(),
      };
      if (!(_openlistPasswordMasked && openlistPassword.contains('***'))) {
        payload['openlist_password'] = openlistPassword;
      }
      if (!(_smtpPasswordMasked && smtpPassword.contains('***'))) {
        payload['backup_email_smtp_password'] = smtpPassword;
      }
      await widget.api.client.patch('/api/admin/settings', payload);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('云端备份配置已保存')));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _runServerBackup() async {
    setState(() => _runningServerBackup = true);
    try {
      await widget.api.runServerBackup();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('服务器备份已执行')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _runningServerBackup = false);
    }
  }

  Future<void> _wipe(Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: Text('清空 ${row['username']} 的云端备份?'),
        icon: const Icon(Icons.cloud_off_outlined),
        content: const Text('账号保留，但服务器上的同步数据会清零，用户下次同步后本地数据将被覆盖。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.wipeBackup(row['user_id'].toString());
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final totalKb = _backups.fold<int>(
      0,
      (s, e) => s + ((e['size_kb'] as int?) ?? 0),
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AppSettingsSection(
          title: '云端备份',
          subtitle: '限制同步体积、频率与服务开关',
          children: [
            AppSwitchTile(
              icon: Icons.cloud_sync_outlined,
              color: cs.primary,
              value: _backupEnabled,
              title: '启用云端备份',
              subtitle: '关闭后所有 /api/sync 请求会被拒绝',
              onChanged: (v) => setState(() => _backupEnabled = v),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _maxSizeCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '单用户同步大小上限 (KB)',
                helperText: '0 = 不限，默认 2048',
                prefixIcon: Icon(Icons.storage_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _intervalCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '客户端最小自动同步间隔 (分钟)',
                helperText: '用于客户端回退策略参考',
                prefixIcon: Icon(Icons.update_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _retainCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '备份历史保留天数',
                helperText: '0 = 永久保留 (当前后端仅保留最新快照)',
                prefixIcon: Icon(Icons.history_outlined),
              ),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(_saving ? '保存中…' : '保存'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        AppSettingsSection(
          title: '服务器备份',
          subtitle: '定期打包后台数据库，上传到 OpenList，并可邮件通知',
          children: [
            AppSwitchTile(
              icon: Icons.dns_outlined,
              color: Colors.indigo,
              value: _serverBackupEnabled,
              title: '启用服务器定期备份',
              subtitle: '后台进程按间隔生成数据库 ZIP 快照',
              onChanged: (v) => setState(() => _serverBackupEnabled = v),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _serverIntervalCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '服务器备份间隔 (分钟)',
                      prefixIcon: Icon(Icons.schedule_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _serverRetainCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '本地保留天数',
                      prefixIcon: Icon(Icons.history_toggle_off_outlined),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AppSwitchTile(
              icon: Icons.cloud_upload_outlined,
              color: Colors.blue,
              value: _openlistEnabled,
              title: '上传到 OpenList',
              subtitle: '使用 OpenList WebDAV 保存服务器备份包',
              onChanged: (v) => setState(() => _openlistEnabled = v),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _openlistUrlCtrl,
              decoration: const InputDecoration(
                labelText: 'OpenList WebDAV URL',
                hintText: 'http://127.0.0.1:5244/dav',
                prefixIcon: Icon(Icons.link_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _openlistPublicUrlCtrl,
              decoration: const InputDecoration(
                labelText: 'OpenList 公开 URL (可选)',
                prefixIcon: Icon(Icons.public_outlined),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _openlistUserCtrl,
                    decoration: const InputDecoration(
                      labelText: 'OpenList 用户名',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _openlistPasswordCtrl,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'OpenList 密码',
                      helperText: _openlistPasswordMasked
                          ? '已配置，保持不动即不修改'
                          : null,
                      prefixIcon: const Icon(Icons.password_outlined),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _openlistPathCtrl,
              decoration: const InputDecoration(
                labelText: 'OpenList 备份目录',
                hintText: '/duoyi-backups',
                prefixIcon: Icon(Icons.folder_outlined),
              ),
            ),
            const SizedBox(height: 12),
            AppSwitchTile(
              icon: Icons.mark_email_read_outlined,
              color: Colors.teal,
              value: _backupEmailEnabled,
              title: '备份完成后发送邮件',
              subtitle: '支持 SMTP，失败会写入备份记录',
              onChanged: (v) => setState(() => _backupEmailEnabled = v),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _emailToCtrl,
                    decoration: const InputDecoration(
                      labelText: '通知收件人',
                      prefixIcon: Icon(Icons.alternate_email),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _emailFromCtrl,
                    decoration: const InputDecoration(
                      labelText: '发件人',
                      prefixIcon: Icon(Icons.outgoing_mail),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _smtpHostCtrl,
              decoration: const InputDecoration(
                labelText: 'SMTP Host',
                prefixIcon: Icon(Icons.dns_outlined),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _smtpPortCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'SMTP 端口',
                      prefixIcon: Icon(Icons.numbers_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _smtpUserCtrl,
                    decoration: const InputDecoration(
                      labelText: 'SMTP 用户名',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _smtpPasswordCtrl,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'SMTP 密码',
                helperText: _smtpPasswordMasked ? '已配置，保持不动即不修改' : null,
                prefixIcon: const Icon(Icons.key_outlined),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_saving ? '保存中…' : '保存配置'),
                ),
                OutlinedButton.icon(
                  onPressed: _runningServerBackup ? null : _runServerBackup,
                  icon: _runningServerBackup
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.backup_outlined),
                  label: Text(_runningServerBackup ? '备份中…' : '立即备份'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        AppSectionHeader(
          title: '服务器备份记录',
          subtitle: '${_serverBackups.length} 条',
        ),
        const SizedBox(height: 6),
        if (_serverBackups.isEmpty)
          Text(
            '暂无服务器备份',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurface.withValues(alpha: 0.58),
            ),
          ),
        ..._serverBackups.take(10).map((b) {
          final status = (b['status'] ?? '-').toString();
          return AppListTileCard(
            margin: const EdgeInsets.only(bottom: 8),
            dense: true,
            leading: Icon(Icons.backup_outlined, color: cs.primary),
            title: Text((b['filename'] ?? '-').toString()),
            subtitle: Text(
              '${b['created_at'] ?? '-'} · $status · ${b['size_bytes'] ?? 0} bytes',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurface.withValues(alpha: 0.62),
              ),
            ),
          );
        }),
        const SizedBox(height: 12),
        AppSectionHeader(
          title: '所有用户备份',
          subtitle:
              '${_backups.length} 个 · ${(totalKb / 1024).toStringAsFixed(1)} MB',
        ),
        const SizedBox(height: 6),
        if (_backups.isEmpty)
          Text(
            '暂无备份',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurface.withValues(alpha: 0.58),
            ),
          ),
        ..._backups.map((b) {
          return AppListTileCard(
            margin: const EdgeInsets.only(bottom: 8),
            dense: true,
            leading: Icon(Icons.cloud_done_outlined, color: cs.primary),
            title: Text(b['username'].toString()),
            subtitle: Text(
              '${b['updated_at'] ?? '-'} · ${b['size_kb']} KB',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurface.withValues(alpha: 0.62),
              ),
            ),
            trailing: IconButton(
              tooltip: '清空备份',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _wipe(b),
            ),
          );
        }),
      ],
    );
  }
}

// ====================================================================
// 用户
// ====================================================================

class _UsersTab extends StatefulWidget {
  final AdminApi api;
  final String? selfId;
  const _UsersTab({required this.api, required this.selfId});
  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> {
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;
  String? _error;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({String? query}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _users = await widget.api.listUsers(query: query);
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleAdmin(Map<String, dynamic> u) async {
    final becomeAdmin = !(u['is_admin'] == true);
    try {
      await widget.api.updateUser(u['user_id'], isAdmin: becomeAdmin);
      u['is_admin'] = becomeAdmin;
      if (mounted) setState(() {});
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _toggleDisable(Map<String, dynamic> u) async {
    final disable = !(u['is_disabled'] == true);
    try {
      await widget.api.updateUser(u['user_id'], isDisabled: disable);
      u['is_disabled'] = disable;
      if (mounted) setState(() {});
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _resetPassword(Map<String, dynamic> u) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: Text('重置 ${u['username']} 的密码'),
        icon: const Icon(Icons.lock_reset_outlined),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: '新密码'),
          obscureText: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('提交'),
          ),
        ],
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    try {
      await widget.api.updateUser(u['user_id'], newPassword: ctrl.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('密码已重置，该用户需重新登录')));
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _delete(Map<String, dynamic> u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: Text('删除 ${u['username']} ?'),
        icon: const Icon(Icons.delete_outline),
        content: const Text('会同时删除其所有同步数据与反馈，不可恢复'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.deleteUser(u['user_id']);
      _users.removeWhere((x) => x['user_id'] == u['user_id']);
      if (mounted) setState(() {});
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    hintText: '按用户名搜索',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                  ),
                  onSubmitted: (v) => _load(query: v.trim()),
                ),
              ),
              IconButton(
                onPressed: () => _load(query: _searchCtrl.text.trim()),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        if (_loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_error != null)
          Expanded(child: Center(child: Text(_error!)))
        else if (_users.isEmpty)
          const Expanded(
            child: EmptyState(icon: Icons.people_outline, message: '无用户'),
          )
        else
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(8),
              itemCount: _users.length,
              separatorBuilder: (context, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final u = _users[i];
                final isSelf = u['user_id'] == widget.selfId;
                final disabled = u['is_disabled'] == true;
                final admin = u['is_admin'] == true;
                final online = u['online'] == true;
                return AppListTileCard(
                  leading: CircleAvatar(
                    backgroundColor: admin
                        ? Colors.deepOrange.withValues(alpha: 0.2)
                        : cs.primary.withValues(alpha: 0.12),
                    foregroundColor: admin ? Colors.deepOrange : cs.primary,
                    child: Text(
                      (u['username'] as String? ?? '?').isEmpty
                          ? '?'
                          : u['username'].toString().substring(0, 1),
                    ),
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          u['username'].toString(),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w400,
                            decoration: disabled
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ),
                      if (online) ...[
                        const SizedBox(width: 6),
                        const AppStatusBadge(
                          label: '在线',
                          color: Colors.green,
                          icon: Icons.circle,
                          padding: EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                        ),
                      ],
                      if (admin) ...[
                        const SizedBox(width: 6),
                        const AppStatusBadge(
                          label: '管理员',
                          color: Colors.deepOrange,
                        ),
                      ],
                      if (disabled) ...[
                        const SizedBox(width: 6),
                        const AppStatusBadge(label: '已禁用', color: Colors.red),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    '注册: ${u['created_at'] ?? '-'} · 最近: ${u['last_login_at'] ?? '-'} · 反馈: ${u['feedback_count'] ?? 0}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.62),
                    ),
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (action) async {
                      switch (action) {
                        case 'admin':
                          await _toggleAdmin(u);
                          break;
                        case 'disable':
                          await _toggleDisable(u);
                          break;
                        case 'reset':
                          await _resetPassword(u);
                          break;
                        case 'delete':
                          await _delete(u);
                          break;
                        case 'copy_id':
                          await Clipboard.setData(
                            ClipboardData(text: u['user_id'].toString()),
                          );
                          if (!context.mounted) return;
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('user_id 已复制')),
                            );
                          }
                          break;
                      }
                    },
                    itemBuilder: (ctx) => [
                      PopupMenuItem(
                        value: 'admin',
                        child: Text(admin ? '取消管理员' : '设为管理员'),
                      ),
                      PopupMenuItem(
                        value: 'disable',
                        child: Text(disabled ? '启用账号' : '禁用账号'),
                      ),
                      const PopupMenuItem(value: 'reset', child: Text('重置密码')),
                      const PopupMenuItem(
                        value: 'copy_id',
                        child: Text('复制 user_id'),
                      ),
                      if (!isSelf)
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text(
                            '删除账号',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

// ====================================================================
// 公告
// ====================================================================

class _AnnouncementsTab extends StatefulWidget {
  final AdminApi api;
  const _AnnouncementsTab({required this.api});
  @override
  State<_AnnouncementsTab> createState() => _AnnouncementsTabState();
}

class _AnnouncementsTabState extends State<_AnnouncementsTab> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _items = await widget.api.listAnnouncements();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _openEdit({Map<String, dynamic>? item}) async {
    final titleCtrl = TextEditingController(
      text: (item?['title'] ?? '').toString(),
    );
    final bodyCtrl = TextEditingController(
      text: (item?['body'] ?? '').toString(),
    );
    String level = (item?['level'] ?? 'info').toString();
    bool published =
        (item?['published'] ?? 1) == 1 || item?['published'] == true;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AppDialog(
          title: Text(item == null ? '新增公告' : '编辑公告'),
          icon: const Icon(Icons.campaign_outlined),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: '标题'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: bodyCtrl,
                  maxLines: 6,
                  decoration: const InputDecoration(labelText: '内容'),
                ),
                const SizedBox(height: 8),
                AppDropdownField<String>(
                  initialValue: level,
                  labelText: '级别',
                  items: const [
                    DropdownMenuItem(value: 'info', child: Text('普通')),
                    DropdownMenuItem(value: 'warning', child: Text('警告')),
                    DropdownMenuItem(value: 'critical', child: Text('紧急')),
                  ],
                  onChanged: (v) => setSt(() => level = v ?? 'info'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: published,
                  title: const Text('立即发布'),
                  onChanged: (v) => setSt(() => published = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    try {
      if (item == null) {
        await widget.api.createAnnouncement(
          title: titleCtrl.text.trim(),
          body: bodyCtrl.text.trim(),
          level: level,
          published: published,
        );
      } else {
        await widget.api.updateAnnouncement(
          (item['id'] as num).toInt(),
          title: titleCtrl.text.trim(),
          body: bodyCtrl.text.trim(),
          level: level,
          published: published,
        );
      }
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
          ? const EmptyState(icon: Icons.campaign_outlined, message: '暂无公告')
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _items.length,
              itemBuilder: (_, i) {
                final a = _items[i];
                final published = a['published'] == 1 || a['published'] == true;
                final level = (a['level'] ?? 'info').toString();
                final levelColor = switch (level) {
                  'critical' => Colors.red,
                  'warning' => Colors.orange,
                  _ => cs.primary,
                };
                return AppListTileCard(
                  margin: const EdgeInsets.only(bottom: 8),
                  isThreeLine: true,
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          (a['title'] ?? '').toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w400,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      AppStatusBadge(label: level, color: levelColor),
                      if (!published) ...[
                        const SizedBox(width: 6),
                        AppStatusBadge(
                          label: '草稿',
                          color: cs.onSurface.withValues(alpha: 0.58),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    '${a['created_at']}\n${(a['body'] ?? '').toString()}',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.64),
                    ),
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (action) async {
                      if (action == 'edit') _openEdit(item: a);
                      if (action == 'toggle') {
                        await widget.api.updateAnnouncement(
                          (a['id'] as num).toInt(),
                          published: !published,
                        );
                        _load();
                      }
                      if (action == 'delete') {
                        await widget.api.deleteAnnouncement(
                          (a['id'] as num).toInt(),
                        );
                        _load();
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'edit', child: Text('编辑')),
                      PopupMenuItem(
                        value: 'toggle',
                        child: Text(published ? '下架' : '发布'),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('删除', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEdit(),
        icon: const Icon(Icons.add),
        label: const Text('发布'),
      ),
    );
  }
}

// ====================================================================
// 反馈
// ====================================================================

class _FeedbackTab extends StatefulWidget {
  final AdminApi api;
  const _FeedbackTab({required this.api});
  @override
  State<_FeedbackTab> createState() => _FeedbackTabState();
}

class _FeedbackTabState extends State<_FeedbackTab> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _items = await widget.api.listFeedback(
        status: _filter.isEmpty ? null : _filter,
      );
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _reply(Map<String, dynamic> f) async {
    final ctrl = TextEditingController(
      text: (f['admin_reply'] ?? '').toString(),
    );
    String status = (f['status'] ?? 'resolved').toString();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AppDialog(
          title: const Text('回复反馈'),
          icon: const Icon(Icons.reply_outlined),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text((f['content'] ?? '').toString()),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                maxLines: 4,
                decoration: const InputDecoration(labelText: '回复内容'),
              ),
              const SizedBox(height: 8),
              AppDropdownField<String>(
                initialValue: status,
                labelText: '处理状态',
                items: const [
                  DropdownMenuItem(value: 'open', child: Text('待处理')),
                  DropdownMenuItem(value: 'in_progress', child: Text('处理中')),
                  DropdownMenuItem(value: 'resolved', child: Text('已解决')),
                  DropdownMenuItem(value: 'closed', child: Text('已关闭')),
                ],
                onChanged: (v) => setSt(() => status = v ?? status),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('提交'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    try {
      await widget.api.replyFeedback(
        feedbackId: (f['id'] as num).toInt(),
        reply: ctrl.text.trim(),
        status: status,
      );
      _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                _filterChip('全部', ''),
                _filterChip('待处理', 'open'),
                _filterChip('处理中', 'in_progress'),
                _filterChip('已解决', 'resolved'),
                _filterChip('已关闭', 'closed'),
              ],
            ),
          ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_items.isEmpty)
            const Expanded(
              child: EmptyState(icon: Icons.inbox_outlined, message: '没有反馈'),
            )
          else
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: _items.length,
                itemBuilder: (_, i) {
                  final f = _items[i];
                  final status = (f['status'] ?? 'open').toString();
                  final statusColor = switch (status) {
                    'resolved' => Colors.green,
                    'closed' => Colors.grey,
                    'in_progress' => Colors.orange,
                    _ => cs.primary,
                  };
                  final reply = (f['admin_reply'] ?? '').toString();
                  return AppListTileCard(
                    margin: const EdgeInsets.only(bottom: 8),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${f['username']} · ${f['category']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.onSurface,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        AppStatusBadge(label: status, color: statusColor),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (f['content'] ?? '').toString(),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                        if (reply.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.teal.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.teal.withValues(alpha: 0.16),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.subdirectory_arrow_right,
                                    size: 16,
                                    color: Colors.teal,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      '回复: $reply',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: cs.onSurface.withValues(
                                              alpha: 0.68,
                                            ),
                                            fontWeight: FontWeight.w400,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: '回复',
                          icon: const Icon(Icons.reply),
                          onPressed: () => _reply(f),
                        ),
                        IconButton(
                          tooltip: '删除',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            await widget.api.deleteFeedback(
                              (f['id'] as num).toInt(),
                            );
                            _load();
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final selected = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) {
          setState(() => _filter = value);
          _load();
        },
      ),
    );
  }
}

// ====================================================================
// 邀请码
// ====================================================================

class _InvitesTab extends StatefulWidget {
  final AdminApi api;
  const _InvitesTab({required this.api});
  @override
  State<_InvitesTab> createState() => _InvitesTabState();
}

class _InvitesTabState extends State<_InvitesTab> {
  List<Map<String, dynamic>> _codes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _codes = await widget.api.listInviteCodes();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _generate() async {
    int count = 5;
    String note = '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AppDialog(
          title: const Text('生成邀请码'),
          icon: const Icon(Icons.vpn_key_outlined),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Text('数量:'),
                  Expanded(
                    child: Slider(
                      value: count.toDouble(),
                      min: 1,
                      max: 50,
                      divisions: 49,
                      label: '$count',
                      onChanged: (v) => setSt(() => count = v.toInt()),
                    ),
                  ),
                  Text('$count'),
                ],
              ),
              TextField(
                decoration: const InputDecoration(labelText: '备注 (可选)'),
                onChanged: (v) => note = v,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('生成'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      final codes = await widget.api.createInviteCodes(
        count: count,
        note: note,
      );
      await _load();
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AppDialog(
          title: Text('已生成 ${codes.length} 个邀请码'),
          icon: const Icon(Icons.check_circle_outline),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: SelectableText(codes.join('\n')),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: codes.join('\n')));
                Navigator.pop(ctx);
              },
              child: const Text('复制并关闭'),
            ),
          ],
        ),
      );
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _codes.isEmpty
          ? const EmptyState(icon: Icons.vpn_key_outlined, message: '尚无邀请码')
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _codes.length,
              itemBuilder: (_, i) {
                final c = _codes[i];
                final used = (c['used_by'] ?? '').toString().isNotEmpty;
                return AppListTileCard(
                  margin: const EdgeInsets.only(bottom: 8),
                  leading: Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: (used ? Colors.grey : Colors.blue).withValues(
                        alpha: 0.12,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      used ? Icons.check_circle : Icons.key,
                      color: used ? Colors.grey : Colors.blue,
                    ),
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          c['code'].toString(),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w400,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                      AppStatusBadge(
                        label: used ? '已使用' : '未使用',
                        color: used ? Colors.grey : Colors.blue,
                      ),
                    ],
                  ),
                  subtitle: Text(
                    used
                        ? '已被 ${c['used_by_name'] ?? '?'} 使用 · ${c['used_at']}'
                        : '创建 ${c['created_at']}${(c['note'] ?? '').toString().isNotEmpty ? ' · ${c['note']}' : ''}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.62),
                    ),
                  ),
                  trailing: used
                      ? null
                      : IconButton(
                          tooltip: '删除',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            await widget.api.deleteInviteCode(
                              c['code'].toString(),
                            );
                            _load();
                          },
                        ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _generate,
        icon: const Icon(Icons.add),
        label: const Text('生成'),
      ),
    );
  }
}
