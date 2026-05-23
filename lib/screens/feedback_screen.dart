import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/i18n.dart';
import '../providers/auth_provider.dart';
import '../services/api_client.dart';
import '../widgets/empty_state.dart';
import '../widgets/surface_components.dart';
import 'login_screen.dart';

class FeedbackScreen extends StatefulWidget {
  final String initialCategory;

  const FeedbackScreen({super.key, this.initialCategory = 'feature'});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  static const int _pageSize = 10;

  late String _category;
  final _contentCtrl = TextEditingController();
  final List<Map<String, dynamic>> _items = [];
  bool _loading = false;
  bool _submitting = false;
  String? _error;
  int _page = 1;
  int _totalPages = 1;
  int _total = 0;
  int _loadSerial = 0;

  @override
  void initState() {
    super.initState();
    _category = _normalizeCategory(widget.initialCategory);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _contentCtrl.dispose();
    super.dispose();
  }

  String _normalizeCategory(String value) {
    return switch (value) {
      'bug' => 'bug',
      'wish' => 'wish',
      'other' => 'other',
      _ => 'feature',
    };
  }

  String _categoryLabel(String value) => switch (value) {
    'bug' => I18n.tr('feedback.category.bug'),
    'wish' => I18n.tr('feedback.category.wish'),
    'other' => I18n.tr('feedback.category.other'),
    _ => I18n.tr('feedback.category.feature'),
  };

  String _categoryHelp(String value) => switch (value) {
    'bug' => I18n.tr('feedback.help.bug'),
    'wish' => I18n.tr('feedback.help.wish'),
    'other' => I18n.tr('feedback.help.other'),
    _ => I18n.tr('feedback.help.feature'),
  };

  String _statusLabel(String value) => switch (value) {
    'resolved' => I18n.tr('feedback.status.resolved'),
    'closed' => I18n.tr('feedback.status.closed'),
    'in_progress' => I18n.tr('feedback.status.in_progress'),
    _ => I18n.tr('feedback.status.open'),
  };

  Color _statusColor(BuildContext context, String value) {
    return switch (value) {
      'resolved' => Colors.green,
      'closed' => Theme.of(context).colorScheme.onSurfaceVariant,
      'in_progress' => Colors.orange,
      _ => Theme.of(context).colorScheme.primary,
    };
  }

  Future<void> _load({int? page}) async {
    final auth = context.read<AuthProvider>();
    if (!auth.state.isLoggedIn) return;
    final loadSerial = ++_loadSerial;
    final nextPage = page ?? _page;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final path = '/api/feedback/me?page=$nextPage&page_size=$_pageSize';
      final raw = await auth.client.getRaw(path);
      final res = raw is Map<String, dynamic> ? raw : <String, dynamic>{};
      final list = raw is List<dynamic>
          ? raw
          : (res['items'] as List<dynamic>? ?? const []);
      final rawItems = list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (!mounted || loadSerial != _loadSerial) return;
      setState(() {
        _items
          ..clear()
          ..addAll(rawItems);
        _page = raw is Map ? ((res['page'] as num?) ?? nextPage).toInt() : 1;
        _totalPages = raw is Map
            ? ((res['total_pages'] as num?) ?? 1).toInt().clamp(1, 999999)
            : 1;
        _total = raw is Map
            ? ((res['total'] as num?) ?? rawItems.length).toInt()
            : rawItems.length;
      });
    } on ApiException catch (e) {
      if (mounted && loadSerial == _loadSerial) {
        setState(() => _error = e.message);
      }
    } catch (e) {
      if (mounted && loadSerial == _loadSerial) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted && loadSerial == _loadSerial) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _submit() async {
    final auth = context.read<AuthProvider>();
    if (!auth.state.isLoggedIn) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      return;
    }
    final content = _contentCtrl.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(I18n.tr('feedback.content.empty'))),
      );
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await auth.client.post('/api/feedback', {
        'category': _category,
        'content': content,
      });
      _contentCtrl.clear();
      if (!mounted) return;
      Navigator.of(context).pop();
      await _load(page: 1);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(I18n.tr('feedback.submitted'))));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _openSubmitSheet() {
    showAppModalSheet<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setSheetState) {
          return AppModalSheet(
            title: I18n.tr('feedback.submit.button'),
            subtitle: _categoryHelp(_category),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _FeedbackCategoryMenu(
                  selected: _category,
                  labelFor: _categoryLabel,
                  onSelected: (value) {
                    final next = _normalizeCategory(value);
                    setState(() => _category = next);
                    setSheetState(() {});
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _contentCtrl,
                  minLines: 5,
                  maxLines: 8,
                  decoration: InputDecoration(
                    labelText:
                        '${I18n.tr('feedback.content.label_prefix')}${_categoryLabel(_category)}',
                    helperText: _categoryHelp(_category),
                    alignLabelWithHint: true,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: TextStyle(color: Colors.red.shade600)),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _submitting ? null : _submit,
                    icon: _submitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_outlined),
                    label: Text(
                      _submitting
                          ? I18n.tr('feedback.submitting')
                          : I18n.tr('feedback.submit.button'),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final loggedIn = auth.state.isLoggedIn;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('许愿与反馈')),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('feedback_submit_fab'),
        onPressed: loggedIn ? _openSubmitSheet : null,
        icon: const Icon(Icons.add_comment_outlined),
        label: Text(I18n.tr('feedback.submit.button')),
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(page: _page),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
          children: [
            AppSurfaceCard(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.forum_outlined, color: cs.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppSectionHeader(
                          title: '反馈记录',
                          padding: EdgeInsets.zero,
                          titleStyle: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          loggedIn
                              ? '共 $_total 条，当前第 $_page/$_totalPages 页'
                              : I18n.tr('feedback.login.records_required'),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: cs.onSurface.withValues(alpha: 0.64),
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _FeedbackCategoryMenu(
              selected: _category,
              labelFor: _categoryLabel,
              onSelected: (value) =>
                  setState(() => _category = _normalizeCategory(value)),
            ),
            if (!loggedIn) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(
                  onPressed: null,
                  child: Text(I18n.tr('feedback.submit.button')),
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (!loggedIn)
              EmptyState(
                icon: Icons.login_outlined,
                message: I18n.tr('feedback.login.records_required'),
                actionLabel:
                    '${I18n.tr('feedback.submit.login_prefix')}${_categoryLabel(_category)}',
              )
            else if (_loading && _items.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_error != null && _items.isEmpty)
              EmptyState(
                icon: Icons.error_outline,
                message: _error!,
                actionLabel: I18n.tr('feedback.refresh'),
                onAction: () => _load(page: _page),
              )
            else if (_items.isEmpty)
              EmptyState(
                icon: Icons.feedback_outlined,
                message: I18n.tr('feedback.empty'),
                actionLabel: I18n.tr('feedback.submit.button'),
                onAction: _openSubmitSheet,
              )
            else ...[
              ..._items.map(
                (item) => _FeedbackRecordCard(
                  item: item,
                  categoryLabel: _categoryLabel,
                  statusLabel: _statusLabel,
                  statusColor: (status) => _statusColor(context, status),
                ),
              ),
              const SizedBox(height: 8),
              _FeedbackPagination(
                key: const ValueKey('feedback_record_pagination'),
                page: _page,
                totalPages: _totalPages,
                loading: _loading,
                onPrevious: _page <= 1 ? null : () => _load(page: _page - 1),
                onNext: _page >= _totalPages
                    ? null
                    : () => _load(page: _page + 1),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FeedbackCategoryMenu extends StatelessWidget {
  final String selected;
  final String Function(String) labelFor;
  final ValueChanged<String> onSelected;

  const _FeedbackCategoryMenu({
    required this.selected,
    required this.labelFor,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      key: const ValueKey('feedback_three_level_menu'),
      children: [
        Text(
          '三级菜单',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: cs.onSurface.withValues(alpha: 0.54),
          ),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<String>(
          tooltip: I18n.tr('feedback.category.label'),
          initialValue: selected,
          onSelected: onSelected,
          itemBuilder: (_) => [
            for (final category in const ['feature', 'bug', 'wish'])
              PopupMenuItem(
                value: category,
                child: Row(
                  children: [
                    Expanded(child: Text(labelFor(category))),
                    if (selected == category)
                      Icon(Icons.check, size: 16, color: cs.primary),
                  ],
                ),
              ),
          ],
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: cs.primary.withValues(alpha: 0.28)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  labelFor(selected),
                  style: TextStyle(color: cs.primary, fontSize: 13),
                ),
                const SizedBox(width: 4),
                Icon(Icons.arrow_drop_down, color: cs.primary, size: 18),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FeedbackRecordCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final String Function(String) categoryLabel;
  final String Function(String) statusLabel;
  final Color Function(String) statusColor;

  const _FeedbackRecordCard({
    required this.item,
    required this.categoryLabel,
    required this.statusLabel,
    required this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    final category = (item['category'] ?? 'feature').toString();
    final status = (item['status'] ?? 'open').toString();
    final content = (item['content'] ?? '').toString();
    final reply = (item['admin_reply'] ?? '').toString();
    final createdAt = (item['created_at'] ?? '').toString();
    final color = statusColor(status);
    final cs = Theme.of(context).colorScheme;
    return AppSurfaceCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  categoryLabel(category),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              AppStatusBadge(label: statusLabel(status), color: color),
            ],
          ),
          if (createdAt.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              createdAt,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.onSurface.withValues(alpha: 0.52),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(content),
          if (reply.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.42),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    I18n.tr('feedback.admin_reply'),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(reply),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FeedbackPagination extends StatelessWidget {
  final int page;
  final int totalPages;
  final bool loading;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const _FeedbackPagination({
    super.key,
    required this.page,
    required this.totalPages,
    required this.loading,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: loading ? null : onPrevious,
            icon: const Icon(Icons.chevron_left),
            label: const Text('上一页'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('第 $page/$totalPages 页'),
        ),
        Expanded(
          child: FilledButton.tonalIcon(
            onPressed: loading ? null : onNext,
            icon: const Icon(Icons.chevron_right),
            label: const Text('下一页'),
          ),
        ),
      ],
    );
  }
}
