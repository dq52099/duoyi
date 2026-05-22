/// 集成中心：日历订阅 + 位置提醒 + 语言设置（Task T-* 集成 UI）。
///
/// 把 v2 阶段新增的三类"边缘能力"集中在一个 Tab 化页面里：
/// - 日历订阅：用户粘贴 .ics URL 即可让多仪日历显示外部日程；
/// - 位置提醒：手动录入坐标 + 半径 + 触发方向；
/// - 语言：在中 / 英 之间切换。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/i18n.dart';
import '../core/i18n_date_format.dart';
import '../models/location_reminder.dart';
import '../providers/location_reminder_provider.dart';
import '../providers/notification_service.dart';
import '../services/calendar_sync_service.dart';
import '../services/location_geofence_service.dart';
import '../widgets/surface_components.dart';

class IntegrationsScreen extends StatelessWidget {
  final Uri? initialOAuthCallbackUri;

  const IntegrationsScreen({super.key, this.initialOAuthCallbackUri});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('扩展集成'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '日历订阅'),
              Tab(text: '位置提醒'),
              Tab(text: '语言'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _CalendarSubscriptionsTab(
              initialOAuthCallbackUri: initialOAuthCallbackUri,
            ),
            const _LocationRemindersTab(),
            const _LocaleTab(),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 日历订阅
// ---------------------------------------------------------------------------

class _CalendarSubscriptionsTab extends StatefulWidget {
  final Uri? initialOAuthCallbackUri;

  const _CalendarSubscriptionsTab({this.initialOAuthCallbackUri});

  @override
  State<_CalendarSubscriptionsTab> createState() =>
      _CalendarSubscriptionsTabState();
}

class _CalendarSubscriptionsTabState extends State<_CalendarSubscriptionsTab> {
  bool _handledInitialOAuthCallback = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleInitialOAuthCallback();
    });
  }

  @override
  void didUpdateWidget(covariant _CalendarSubscriptionsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialOAuthCallbackUri != widget.initialOAuthCallbackUri) {
      _handledInitialOAuthCallback = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleInitialOAuthCallback();
      });
    }
  }

  void _handleInitialOAuthCallback() {
    if (!mounted ||
        _handledInitialOAuthCallback ||
        widget.initialOAuthCallbackUri == null) {
      return;
    }
    _handledInitialOAuthCallback = true;
    _OAuthCalendarCard.showOAuthDialog(
      context,
      context.read<CalendarSyncProvider>(),
      callbackUri: widget.initialOAuthCallbackUri,
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CalendarSyncProvider>();
    final subs = provider.subscriptions;
    final oauthAccounts = provider.oauthAccounts;
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AppSurfaceCard(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.event_available, size: 18),
                        const SizedBox(width: 8),
                        const Text(
                          '从 ICS URL 订阅',
                          style: TextStyle(fontWeight: FontWeight.w400),
                        ),
                        const Spacer(),
                        if (provider.isSyncing)
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '支持 Google / Outlook / Apple iCloud 公开日历、企业 iCal feed、'
                      '部分 CalDAV 服务器的导出端点。订阅为只读，'
                      '不会修改远端日历。',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _OAuthCalendarCard(provider: provider),
            const SizedBox(height: 12),
            for (final account in oauthAccounts)
              _OAuthCalendarTile(account: account),
            if (oauthAccounts.isNotEmpty) const SizedBox(height: 4),
            _CalDavWriteTargetCard(provider: provider),
            const SizedBox(height: 12),
            for (final s in subs) _SubscriptionTile(sub: s),
            if (subs.isEmpty && oauthAccounts.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    '还没有订阅，点击右下角 + 添加 ICS，或添加 Google / Outlook 账号',
                    style: TextStyle(color: Colors.black45),
                  ),
                ),
              ),
            const SizedBox(height: 80),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            heroTag: 'ics_add',
            onPressed: () => _showAddDialog(context, provider),
            child: const Icon(Icons.add),
          ),
        ),
        if (provider.subscriptions.isNotEmpty || oauthAccounts.isNotEmpty)
          Positioned(
            right: 88,
            bottom: 22,
            child: FilledButton.tonalIcon(
              onPressed: provider.isSyncing
                  ? null
                  // ignore: discarded_futures
                  : () => provider.syncAll(),
              icon: const Icon(Icons.refresh),
              label: const Text('刷新'),
            ),
          ),
      ],
    );
  }

  Future<void> _showAddDialog(
    BuildContext context,
    CalendarSyncProvider provider,
  ) async {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: const Text('添加日历订阅'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: '名称'),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlCtrl,
              decoration: const InputDecoration(
                labelText: 'ICS URL',
                hintText: 'https://...',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(I18n.tr('action.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(I18n.tr('action.add')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final name = nameCtrl.text.trim();
    final url = urlCtrl.text.trim();
    if (name.isEmpty || url.isEmpty) return;
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    await provider.addSubscription(
      IcsSubscription(id: id, name: name, url: url),
    );
    // ignore: discarded_futures
    provider.syncAll();
  }
}

class _OAuthCalendarCard extends StatelessWidget {
  final CalendarSyncProvider provider;

  const _OAuthCalendarCard({required this.provider});

  @override
  Widget build(BuildContext context) {
    final hasAccounts = provider.oauthAccounts.isNotEmpty;
    return AppSurfaceCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.account_tree_outlined,
                  size: 18,
                  color: hasAccounts ? Colors.green : Colors.blueGrey,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Google / Outlook OAuth 日历',
                    style: TextStyle(fontWeight: FontWeight.w400),
                  ),
                ),
                if (provider.isSyncing)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              '通过授权码 + PKCE 连接私有 Google Calendar 或 Outlook Calendar，'
              '自动刷新 token 并把远端事件并入本地日历视图。',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: () => showOAuthDialog(context, provider),
                icon: const Icon(Icons.add_link, size: 16),
                label: const Text('添加账号'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> showOAuthDialog(
    BuildContext context,
    CalendarSyncProvider provider, {
    Uri? callbackUri,
  }) async {
    var selectedProvider = OAuthCalendarProvider.google;
    final nameCtrl = TextEditingController(text: selectedProvider.label);
    final clientIdCtrl = TextEditingController();
    final clientSecretCtrl = TextEditingController();
    final redirectCtrl = TextEditingController(text: 'duoyi://oauth/calendar');
    final calendarIdCtrl = TextEditingController(text: 'primary');
    final codeCtrl = TextEditingController(text: callbackUri?.toString() ?? '');
    var codeVerifier = OAuthCalendarClient.generateCodeVerifier();
    var oauthState = OAuthCalendarClient.generateCodeVerifier();

    void disposeControllers() {
      nameCtrl.dispose();
      clientIdCtrl.dispose();
      clientSecretCtrl.dispose();
      redirectCtrl.dispose();
      calendarIdCtrl.dispose();
      codeCtrl.dispose();
    }

    if (callbackUri != null) {
      final pending = await provider.loadPendingOAuthAuthorization();
      if (!context.mounted) {
        disposeControllers();
        return;
      }
      if (pending.isNotEmpty) {
        final pendingState = pending['state'] ?? '';
        final callbackState = callbackUri.queryParameters['state'] ?? '';
        if (pendingState.isNotEmpty && callbackState != pendingState) {
          disposeControllers();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('OAuth 回调 state 不匹配，请重新授权')),
          );
          return;
        }
        selectedProvider = OAuthCalendarProvider.fromName(pending['provider']);
        nameCtrl.text = pending['displayName']?.isNotEmpty == true
            ? pending['displayName']!
            : selectedProvider.label;
        clientIdCtrl.text = pending['clientId'] ?? '';
        clientSecretCtrl.text = pending['clientSecret'] ?? '';
        redirectCtrl.text = pending['redirectUri'] ?? 'duoyi://oauth/calendar';
        calendarIdCtrl.text = pending['calendarId']?.isNotEmpty == true
            ? pending['calendarId']!
            : 'primary';
        if (pending['codeVerifier']?.isNotEmpty == true) {
          codeVerifier = pending['codeVerifier']!;
        }
        if (pendingState.isNotEmpty) {
          oauthState = pendingState;
        }
      }
    }

    Uri? buildAuthUri() {
      final clientId = clientIdCtrl.text.trim();
      final redirectUri = redirectCtrl.text.trim();
      if (clientId.isEmpty || redirectUri.isEmpty) return null;
      return provider.buildOAuthAuthorizationUri(
        provider: selectedProvider,
        clientId: clientId,
        redirectUri: redirectUri,
        codeVerifier: codeVerifier,
        state: oauthState,
      );
    }

    Future<void> savePendingAuthorization(Uri authUri) async {
      await provider.savePendingOAuthAuthorization(
        provider: selectedProvider,
        displayName: nameCtrl.text.trim().isEmpty
            ? selectedProvider.label
            : nameCtrl.text.trim(),
        clientId: clientIdCtrl.text.trim(),
        clientSecret: clientSecretCtrl.text.trim(),
        redirectUri: redirectCtrl.text.trim(),
        calendarId: calendarIdCtrl.text.trim().isEmpty
            ? 'primary'
            : calendarIdCtrl.text.trim(),
        codeVerifier: codeVerifier,
        state: oauthState,
      );
      await Clipboard.setData(ClipboardData(text: authUri.toString()));
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogContext, setState) {
          final authUri = buildAuthUri();
          return AppDialog(
            title: const Text('添加 OAuth 日历'),
            maxWidth: 560,
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<OAuthCalendarProvider>(
                      initialValue: selectedProvider,
                      decoration: const InputDecoration(labelText: '服务商'),
                      items: [
                        for (final p in OAuthCalendarProvider.values)
                          DropdownMenuItem(value: p, child: Text(p.label)),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          selectedProvider = value;
                          if (nameCtrl.text.trim().isEmpty ||
                              OAuthCalendarProvider.values.any(
                                (p) => p.label == nameCtrl.text.trim(),
                              )) {
                            nameCtrl.text = value.label;
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: '显示名称'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: clientIdCtrl,
                      decoration: const InputDecoration(labelText: 'Client ID'),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: clientSecretCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Client Secret（可选）',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: redirectCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Redirect URI',
                        hintText: 'duoyi://oauth/calendar',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: calendarIdCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Calendar ID',
                        hintText: 'primary',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '授权链接',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          const SizedBox(height: 6),
                          SelectableText(
                            authUri?.toString() ?? '填写 Client ID 后生成',
                            style: const TextStyle(fontSize: 11),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: authUri == null
                                    ? null
                                    : () async {
                                        await savePendingAuthorization(authUri);
                                        if (!dialogContext.mounted) return;
                                        ScaffoldMessenger.of(
                                          dialogContext,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text('授权链接已复制'),
                                          ),
                                        );
                                      },
                                icon: const Icon(Icons.copy, size: 16),
                                label: const Text('复制'),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: authUri == null
                                    ? null
                                    : () async {
                                        await savePendingAuthorization(authUri);
                                        final opened = await launchUrl(
                                          authUri,
                                          mode: LaunchMode.externalApplication,
                                        );
                                        if (!dialogContext.mounted) return;
                                        if (!opened) {
                                          ScaffoldMessenger.of(
                                            dialogContext,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text('无法打开授权页，已保留链接'),
                                            ),
                                          );
                                        }
                                      },
                                icon: const Icon(Icons.open_in_new, size: 16),
                                label: const Text('打开'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: codeCtrl,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: '授权码或回调 URL',
                        hintText: '粘贴 code，或粘贴带 ?code= 的回调 URL',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(I18n.tr('action.cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('保存并同步'),
              ),
            ],
          );
        },
      ),
    );

    final displayName = nameCtrl.text.trim();
    final clientId = clientIdCtrl.text.trim();
    final redirectUri = redirectCtrl.text.trim();
    final authorizationCode = codeCtrl.text.trim();
    final clientSecret = clientSecretCtrl.text.trim();
    final calendarId = calendarIdCtrl.text.trim();
    disposeControllers();
    if (ok != true) return;
    if (displayName.isEmpty ||
        clientId.isEmpty ||
        redirectUri.isEmpty ||
        authorizationCode.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请填写名称、Client ID、回调地址和授权码')));
      return;
    }
    try {
      await provider.addOAuthAccountFromCode(
        provider: selectedProvider,
        displayName: displayName,
        clientId: clientId,
        clientSecret: clientSecret,
        redirectUri: redirectUri,
        authorizationCode: authorizationCode,
        codeVerifier: codeVerifier,
        calendarId: calendarId.isEmpty ? 'primary' : calendarId,
      );
      await provider.clearPendingOAuthAuthorization();
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('OAuth 日历已连接')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('连接失败：$e')));
    }
  }
}

class _OAuthCalendarTile extends StatelessWidget {
  final OAuthCalendarAccount account;

  const _OAuthCalendarTile({required this.account});

  @override
  Widget build(BuildContext context) {
    final provider = context.read<CalendarSyncProvider>();
    final color = Color(account.colorValue);
    return AppSurfaceCard(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.2),
          child: Icon(
            account.provider == OAuthCalendarProvider.google
                ? Icons.calendar_month_outlined
                : Icons.mail_outline,
            color: color,
            size: 18,
          ),
        ),
        title: Text(account.displayName),
        subtitle: Text(
          '${account.provider.label} · ${account.enabled ? "启用" : "暂停"} · '
          '${account.calendarId.isEmpty ? "primary" : account.calendarId}'
          '${account.lastSyncedAt == null ? "" : " · 上次同步 ${_formatDateTime(account.lastSyncedAt!)}"}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) async {
            if (value == 'toggle') {
              await provider.updateOAuthAccount(
                account.copyWith(enabled: !account.enabled),
              );
            } else if (value == 'sync') {
              await provider.syncAll();
            } else if (value == 'delete') {
              await provider.removeOAuthAccount(account.id);
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'toggle',
              child: Text(account.enabled ? '暂停' : '启用'),
            ),
            const PopupMenuItem(value: 'sync', child: Text('同步')),
            const PopupMenuItem(value: 'delete', child: Text('删除')),
          ],
        ),
      ),
    );
  }
}

class _CalDavWriteTargetCard extends StatelessWidget {
  final CalendarSyncProvider provider;

  const _CalDavWriteTargetCard({required this.provider});

  @override
  Widget build(BuildContext context) {
    final target = provider.writeTarget;
    final configured = target?.isConfigured == true;
    return AppSurfaceCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.cloud_sync_outlined,
                  size: 18,
                  color: configured ? Colors.green : Colors.blueGrey,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'CalDAV 写回目标',
                    style: TextStyle(fontWeight: FontWeight.w400),
                  ),
                ),
                if (provider.isTestingWriteTarget)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              configured
                  ? '${target!.enabled ? "已验证" : "未验证"} · ${_conflictPolicyLabel(target.conflictPolicy)} · ${target.collectionUrl}'
                  : '配置 CalDAV 集合 URL 和 Authorization header，测试时会创建并删除一条探测事件。',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            if (provider.lastCalDavConflicts.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                '有 ${provider.lastCalDavConflicts.length} 条远端变更已跳过，避免覆盖别人改过的日程。',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Colors.orange),
              ),
            ],
            if (target?.lastTestedAt != null) ...[
              const SizedBox(height: 4),
              Text(
                '上次测试 ${_formatDateTime(target!.lastTestedAt!)}',
                style: const TextStyle(fontSize: 11, color: Colors.black45),
              ),
            ],
            if (provider.lastError != null) ...[
              const SizedBox(height: 6),
              Text(
                provider.lastError!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Colors.red),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _showCalDavDialog(context, provider),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: Text(configured ? '编辑' : '配置'),
                ),
                if (configured)
                  OutlinedButton.icon(
                    onPressed: provider.isTestingWriteTarget
                        ? null
                        : provider.clearWriteTarget,
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('移除'),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _showICloudCalDavDialog(context, provider),
                  icon: const Icon(Icons.apple, size: 16),
                  label: const Text('iCloud'),
                ),
                FilledButton.tonalIcon(
                  onPressed: !configured || provider.isTestingWriteTarget
                      ? null
                      : provider.testWriteTarget,
                  icon: const Icon(Icons.fact_check_outlined, size: 16),
                  label: const Text('测试写回'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCalDavDialog(
    BuildContext context,
    CalendarSyncProvider provider,
  ) async {
    final current = provider.writeTarget;
    final urlCtrl = TextEditingController(text: current?.collectionUrl ?? '');
    final authCtrl = TextEditingController(
      text: current?.authorizationHeader ?? '',
    );
    var conflictPolicy =
        current?.conflictPolicy ?? CalDavConflictPolicy.skipRemoteChanges;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AppDialog(
          title: const Text('配置 CalDAV 写回'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: urlCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '集合 URL',
                  hintText: 'https://caldav.example.com/calendars/me/default/',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: authCtrl,
                decoration: const InputDecoration(
                  labelText: 'Authorization header',
                  hintText: 'Bearer ... 或 Basic ...',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<CalDavConflictPolicy>(
                initialValue: conflictPolicy,
                decoration: const InputDecoration(labelText: '远端冲突处理'),
                items: const [
                  DropdownMenuItem(
                    value: CalDavConflictPolicy.skipRemoteChanges,
                    child: Text('跳过远端已修改事件'),
                  ),
                  DropdownMenuItem(
                    value: CalDavConflictPolicy.overwriteRemote,
                    child: Text('始终覆盖远端'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => conflictPolicy = value);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(I18n.tr('action.cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    final url = urlCtrl.text.trim();
    final auth = authCtrl.text.trim();
    urlCtrl.dispose();
    authCtrl.dispose();
    if (ok != true || url.isEmpty || auth.isEmpty) return;
    await provider.saveWriteTarget(
      CalDavWriteTarget(
        collectionUrl: url,
        authorizationHeader: auth,
        enabled: current?.enabled == true,
        conflictPolicy: conflictPolicy,
        lastTestedAt: current?.lastTestedAt,
      ),
    );
  }

  Future<void> _showICloudCalDavDialog(
    BuildContext context,
    CalendarSyncProvider provider,
  ) async {
    final current = provider.writeTarget;
    final currentUrl = current?.collectionUrl ?? '';
    final urlCtrl = TextEditingController(
      text: currentUrl.startsWith('https://') ? currentUrl : '',
    );
    final appleIdCtrl = TextEditingController();
    final appPasswordCtrl = TextEditingController();
    var conflictPolicy =
        current?.conflictPolicy ?? CalDavConflictPolicy.skipRemoteChanges;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AppDialog(
          title: const Text('配置 iCloud 日历写回'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                CalDavCredentialHelper.iCloudSetupCopy,
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'iCloud CalDAV 集合 URL',
                  hintText: CalDavCredentialHelper.iCloudCollectionUrlHint,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: appleIdCtrl,
                decoration: const InputDecoration(labelText: 'Apple ID'),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: appPasswordCtrl,
                decoration: const InputDecoration(labelText: 'App 专用密码'),
                obscureText: true,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<CalDavConflictPolicy>(
                initialValue: conflictPolicy,
                decoration: const InputDecoration(labelText: '远端冲突处理'),
                items: const [
                  DropdownMenuItem(
                    value: CalDavConflictPolicy.skipRemoteChanges,
                    child: Text('跳过远端已修改事件'),
                  ),
                  DropdownMenuItem(
                    value: CalDavConflictPolicy.overwriteRemote,
                    child: Text('始终覆盖远端'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => conflictPolicy = value);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(I18n.tr('action.cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    final url = urlCtrl.text.trim();
    final appleId = appleIdCtrl.text.trim();
    final appPassword = appPasswordCtrl.text.trim();
    urlCtrl.dispose();
    appleIdCtrl.dispose();
    appPasswordCtrl.dispose();
    if (ok != true || url.isEmpty || appleId.isEmpty || appPassword.isEmpty) {
      return;
    }
    await provider.saveWriteTarget(
      CalDavWriteTarget(
        collectionUrl: url,
        authorizationHeader: CalDavCredentialHelper.basicAuthorizationHeader(
          username: appleId,
          password: appPassword,
        ),
        enabled: false,
        conflictPolicy: conflictPolicy,
      ),
    );
  }

  String _conflictPolicyLabel(CalDavConflictPolicy policy) {
    return switch (policy) {
      CalDavConflictPolicy.skipRemoteChanges => '远端变更不覆盖',
      CalDavConflictPolicy.overwriteRemote => '覆盖远端',
    };
  }
}

class _SubscriptionTile extends StatelessWidget {
  final IcsSubscription sub;
  const _SubscriptionTile({required this.sub});

  @override
  Widget build(BuildContext context) {
    final provider = context.read<CalendarSyncProvider>();
    return AppSurfaceCard(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Color(sub.colorValue).withValues(alpha: 0.2),
          child: Icon(
            Icons.event_repeat,
            color: Color(sub.colorValue),
            size: 18,
          ),
        ),
        title: Text(sub.name),
        subtitle: Text(
          sub.url,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) async {
            if (value == 'toggle') {
              await provider.updateSubscription(
                sub.copyWith(enabled: !sub.enabled),
              );
            } else if (value == 'delete') {
              await provider.removeSubscription(sub.id);
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'toggle',
              child: Text(sub.enabled ? '暂停' : '启用'),
            ),
            const PopupMenuItem(value: 'delete', child: Text('删除')),
          ],
        ),
      ),
    );
  }
}

String _formatDateTime(DateTime d) => I18nDateFormat.fullDateTime(d);

// ---------------------------------------------------------------------------
// 位置提醒
// ---------------------------------------------------------------------------

class _LocationRemindersTab extends StatelessWidget {
  const _LocationRemindersTab();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LocationReminderProvider>();
    final list = provider.reminders;
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AppSurfaceCard(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '位置提醒',
                      style: TextStyle(fontWeight: FontWeight.w400),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '到达 / 离开指定地点时弹出提醒。前台位置更新会立即触发本地通知；'
                      'Android 已接入系统 geofence 调度，需授予后台位置权限并真机验证。',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () =>
                              _testCurrentLocation(context, provider),
                          icon: const Icon(Icons.my_location_outlined),
                          label: const Text('输入当前位置测试'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () =>
                              _requestLocationPermissions(context, provider),
                          icon: const Icon(Icons.location_searching_outlined),
                          label: const Text('授权后台位置'),
                        ),
                        IconButton.outlined(
                          tooltip: '系统位置设置',
                          onPressed:
                              LocationGeofenceService.openLocationSettings,
                          icon: const Icon(Icons.settings_outlined),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            for (final r in list) _LocationTile(reminder: r),
            if (list.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    '没有位置提醒，点击 + 创建',
                    style: TextStyle(color: Colors.black45),
                  ),
                ),
              ),
            const SizedBox(height: 80),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            heroTag: 'location_add',
            onPressed: () => _addReminder(context, provider),
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }

  Future<void> _addReminder(
    BuildContext context,
    LocationReminderProvider provider,
  ) async {
    final titleCtrl = TextEditingController();
    final latCtrl = TextEditingController();
    final lngCtrl = TextEditingController(text: '');
    final radiusCtrl = TextEditingController(text: '200');
    var trigger = LocationTrigger.enter;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AppDialog(
          title: const Text('新建位置提醒'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(labelText: '标题'),
                autofocus: true,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: latCtrl,
                      decoration: const InputDecoration(labelText: '纬度'),
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: true,
                        decimal: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: lngCtrl,
                      decoration: const InputDecoration(labelText: '经度'),
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: true,
                        decimal: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: radiusCtrl,
                decoration: const InputDecoration(labelText: '半径（米）'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('触发方向'),
                  const Spacer(),
                  ChoiceChip(
                    label: const Text('进入'),
                    selected: trigger == LocationTrigger.enter,
                    onSelected: (_) =>
                        setSt(() => trigger = LocationTrigger.enter),
                  ),
                  const SizedBox(width: 4),
                  ChoiceChip(
                    label: const Text('离开'),
                    selected: trigger == LocationTrigger.leave,
                    onSelected: (_) =>
                        setSt(() => trigger = LocationTrigger.leave),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(I18n.tr('action.cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(I18n.tr('action.save')),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final title = titleCtrl.text.trim();
    final lat = double.tryParse(latCtrl.text.trim());
    final lng = double.tryParse(lngCtrl.text.trim());
    final radius = double.tryParse(radiusCtrl.text.trim()) ?? 200;
    if (title.isEmpty || lat == null || lng == null) return;
    await provider.add(
      LocationReminder(
        title: title,
        latitude: lat,
        longitude: lng,
        radiusMeters: radius,
        trigger: trigger,
      ),
    );
  }

  Future<void> _requestLocationPermissions(
    BuildContext context,
    LocationReminderProvider provider,
  ) async {
    final permission = await LocationGeofenceService.requestPermissions();
    final sync = permission.canScheduleGeofence
        ? await LocationGeofenceService.syncReminders(provider.reminders)
        : null;
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          sync == null
              ? permission.message
              : '后台位置权限已授权，已同步 ${sync.scheduledCount} 条系统 geofence',
        ),
        behavior: SnackBarBehavior.floating,
        action: permission.shouldOpenSettings
            ? SnackBarAction(
                label: '去设置',
                onPressed: LocationGeofenceService.openLocationSettings,
              )
            : null,
      ),
    );
  }

  Future<void> _testCurrentLocation(
    BuildContext context,
    LocationReminderProvider provider,
  ) async {
    final latCtrl = TextEditingController();
    final lngCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: const Text('输入当前位置'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: latCtrl,
                    decoration: const InputDecoration(labelText: '纬度'),
                    keyboardType: const TextInputType.numberWithOptions(
                      signed: true,
                      decimal: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: lngCtrl,
                    decoration: const InputDecoration(labelText: '经度'),
                    keyboardType: const TextInputType.numberWithOptions(
                      signed: true,
                      decimal: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '这会把坐标喂给位置提醒引擎，用来验证到达/离开触发规则。',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(I18n.tr('action.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('测试'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    final lat = double.tryParse(latCtrl.text.trim());
    final lng = double.tryParse(lngCtrl.text.trim());
    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请输入有效经纬度'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final hits = provider.ingestFix(
      LocationFix(latitude: lat, longitude: lng, at: DateTime.now()),
    );
    final notificationService = context.read<NotificationService>();
    for (final hit in hits) {
      notificationService.notifyLocationReminderHit(hit);
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          hits.isEmpty ? '当前位置未命中任何位置提醒' : '已触发 ${hits.length} 条位置提醒',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _LocationTile extends StatelessWidget {
  final LocationReminder reminder;
  const _LocationTile({required this.reminder});

  @override
  Widget build(BuildContext context) {
    final provider = context.read<LocationReminderProvider>();
    return AppSurfaceCard(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const CircleAvatar(
          child: Icon(Icons.location_on_outlined, size: 18),
        ),
        title: Text(reminder.title),
        subtitle: Text(
          '${reminder.latitude.toStringAsFixed(4)}, '
          '${reminder.longitude.toStringAsFixed(4)} · '
          '${reminder.radiusMeters.toStringAsFixed(0)}m · '
          '${reminder.trigger == LocationTrigger.enter ? "进入" : "离开"}触发',
          style: const TextStyle(fontSize: 11),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: () => provider.remove(reminder.id),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 语言
// ---------------------------------------------------------------------------

class _LocaleTab extends StatelessWidget {
  const _LocaleTab();

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleProvider>();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          I18n.tr('settings.language'),
          style: const TextStyle(fontWeight: FontWeight.w400),
        ),
        const SizedBox(height: 12),
        for (final entry in const <(AppLocale, String)>[
          (AppLocale.zh, 'settings.language.zh'),
          (AppLocale.en, 'settings.language.en'),
        ])
          ListTile(
            leading: Icon(
              locale.locale == entry.$1
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
            ),
            title: Text(I18n.tr(entry.$2)),
            onTap: () => locale.setLocale(entry.$1),
          ),
        const SizedBox(height: 16),
        Text(
          I18n.tr('settings.language.description'),
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
      ],
    );
  }
}
