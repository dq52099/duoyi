/// 集成中心：日历订阅 + 位置提醒 + 语言设置（Task T-* 集成 UI）。
///
/// 把 v2 阶段新增的三类"边缘能力"集中在一个 Tab 化页面里：
/// - 日历订阅：用户粘贴 .ics URL 即可让多仪日历显示外部日程；
/// - 位置提醒：手动录入坐标 + 半径 + 触发方向；
/// - 语言：在中 / 英 之间切换。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/i18n.dart';
import '../models/location_reminder.dart';
import '../providers/location_reminder_provider.dart';
import '../services/calendar_sync_service.dart';
import '../widgets/surface_components.dart';

class IntegrationsScreen extends StatelessWidget {
  const IntegrationsScreen({super.key});

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
        body: const TabBarView(
          children: [
            _CalendarSubscriptionsTab(),
            _LocationRemindersTab(),
            _LocaleTab(),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 日历订阅
// ---------------------------------------------------------------------------

class _CalendarSubscriptionsTab extends StatelessWidget {
  const _CalendarSubscriptionsTab();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CalendarSyncProvider>();
    final subs = provider.subscriptions;
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
                          style: TextStyle(fontWeight: FontWeight.w500),
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
                      '支持 Google / Outlook 公开日历、企业 iCal feed、'
                      '部分 CalDAV 服务器的导出端点。订阅为只读，'
                      '不会修改远端日历。',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            for (final s in subs) _SubscriptionTile(sub: s),
            if (subs.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    '还没有订阅，点击右下角 + 添加',
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
        if (provider.subscriptions.isNotEmpty)
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
                  children: const [
                    Text(
                      '位置提醒',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    SizedBox(height: 6),
                    Text(
                      '到达 / 离开指定地点时弹出提醒。当前为前台触发，'
                      '后续会接入后台 geofence。',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
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
        const Text(
          '界面语言',
          style: TextStyle(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 12),
        for (final entry in const <(AppLocale, String)>[
          (AppLocale.zh, '简体中文'),
          (AppLocale.en, 'English'),
        ])
          ListTile(
            leading: Icon(
              locale.locale == entry.$1
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
            ),
            title: Text(entry.$2),
            onTap: () => locale.setLocale(entry.$1),
          ),
        const SizedBox(height: 16),
        const Text(
          '说明：当前 v2 阶段已迁移高频公共词条（按钮、导航、提醒、共享）。'
          '剩余页面文案随后续迭代逐步翻译，未翻译部分会回退到中文显示。',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
      ],
    );
  }
}
