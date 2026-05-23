import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/i18n.dart';
import '../providers/auth_provider.dart';
import '../services/api_client.dart';
import '../widgets/empty_state.dart';
import '../widgets/surface_components.dart';

class FeedbackScreen extends StatefulWidget {
  final String initialCategory;

  const FeedbackScreen({super.key, this.initialCategory = 'feature'});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  bool _loading = true;
  bool _submitting = false;
  List<Map<String, dynamic>> _items = [];
  String? _error;
  late String _category;
  final _contentCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _category = _normalizeCategory(widget.initialCategory);
    _load();
  }

  @override
  void dispose() {
    _contentCtrl.dispose();
    super.dispose();
  }

  String _normalizeCategory(String category) {
    switch (category) {
      case 'feature':
      case 'bug':
      case 'wish':
      case 'other':
        return category;
      default:
        return 'feature';
    }
  }

  Future<void> _load() async {
    final auth = context.read<AuthProvider>();
    if (!auth.state.isLoggedIn) {
      setState(() {
        _loading = false;
        _items = const [];
        _error = I18n.tr('feedback.login.records_required');
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await auth.client.getList('/api/feedback/me');
      _items = list.cast<Map<String, dynamic>>();
    } catch (e) {
      _items = const [];
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final auth = context.read<AuthProvider>();
    final messenger = ScaffoldMessenger.of(context);
    if (!auth.state.isLoggedIn) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(I18n.tr('feedback.login.submit_required')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final text = _contentCtrl.text.trim();
    if (text.isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(I18n.tr('feedback.content.empty')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      await auth.client.post('/api/feedback', {
        'category': _category,
        'content': text,
      });
      if (!mounted) return;
      _contentCtrl.clear();
      messenger.showSnackBar(
        SnackBar(content: Text(I18n.tr('feedback.submitted'))),
      );
      _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'resolved':
        return Colors.green;
      case 'closed':
        return Colors.grey;
      case 'in_progress':
        return Colors.blue;
      default:
        return Colors.orange;
    }
  }

  String _categoryLabel(String category) {
    switch (category) {
      case 'feature':
        return I18n.tr('feedback.category.feature');
      case 'bug':
        return I18n.tr('feedback.category.bug');
      case 'wish':
        return I18n.tr('feedback.category.wish');
      default:
        return I18n.tr('feedback.category.other');
    }
  }

  String _categoryHelp(String category) {
    switch (category) {
      case 'bug':
        return I18n.tr('feedback.help.bug');
      case 'wish':
        return I18n.tr('feedback.help.wish');
      case 'other':
        return I18n.tr('feedback.help.other');
      default:
        return I18n.tr('feedback.help.feature');
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'resolved':
        return I18n.tr('feedback.status.resolved');
      case 'closed':
        return I18n.tr('feedback.status.closed');
      case 'in_progress':
        return I18n.tr('feedback.status.in_progress');
      default:
        return I18n.tr('feedback.status.open');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final cs = Theme.of(context).colorScheme;
    final isLoggedIn = auth.state.isLoggedIn;
    final screenTitle = _categoryLabel(_category);

    return Scaffold(
      appBar: AppBar(title: Text(screenTitle)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
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
                    child: Icon(
                      Icons.feedback_outlined,
                      color: cs.primary,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          screenTitle,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w400,
                                color: cs.onSurface,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          auth.state.isLoggedIn
                              ? _categoryHelp(_category)
                              : I18n.tr('feedback.login.subtitle'),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
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
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final category in const ['feature', 'bug', 'wish'])
                  ChoiceChip(
                    label: Text(_categoryLabel(category)),
                    selected: _category == category,
                    onSelected: _submitting
                        ? null
                        : (_) => setState(() => _category = category),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            AppSettingsSection(
              title: isLoggedIn
                  ? '${I18n.tr('feedback.submit.prefix')}$screenTitle'
                  : '${I18n.tr('feedback.submit.login_prefix')}$screenTitle',
              subtitle: isLoggedIn
                  ? _categoryHelp(_category)
                  : I18n.tr('feedback.login.section_subtitle'),
              children: [
                AppDropdownField<String>(
                  initialValue: _category,
                  labelText: I18n.tr('feedback.category.label'),
                  enabled: isLoggedIn && !_submitting,
                  items: [
                    DropdownMenuItem(
                      value: 'feature',
                      child: Text(I18n.tr('feedback.category.feature')),
                    ),
                    DropdownMenuItem(
                      value: 'bug',
                      child: Text(I18n.tr('feedback.category.bug')),
                    ),
                    DropdownMenuItem(
                      value: 'wish',
                      child: Text(I18n.tr('feedback.category.wish')),
                    ),
                    DropdownMenuItem(
                      value: 'other',
                      child: Text(I18n.tr('feedback.category.other')),
                    ),
                  ],
                  onChanged: (v) => setState(() => _category = v ?? 'feature'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _contentCtrl,
                  enabled: isLoggedIn && !_submitting,
                  minLines: 3,
                  maxLines: 6,
                  decoration: InputDecoration(
                    labelText:
                        '${I18n.tr('feedback.content.label_prefix')}$screenTitle',
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: isLoggedIn && !_submitting ? _submit : null,
                    icon: _submitting
                        ? const SizedBox.square(
                            dimension: 18,
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
            const SizedBox(height: 12),
            AppSectionHeader(
              title: I18n.tr('feedback.mine.title'),
              subtitle: _loading
                  ? I18n.tr('feedback.loading')
                  : _error ?? I18n.tr('feedback.recent'),
              padding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_items.isEmpty)
              EmptyState(
                icon: Icons.feedback_outlined,
                message: _error ?? I18n.tr('feedback.empty'),
                actionLabel: I18n.tr('feedback.refresh'),
                onAction: _load,
              )
            else
              ..._items.map((f) {
                final status = (f['status'] ?? 'open').toString();
                final reply = (f['admin_reply'] ?? '').toString();
                final category = _categoryLabel(
                  (f['category'] ?? '').toString(),
                );
                final statusColor = _statusColor(status);

                return AppSurfaceCard(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              category,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w400,
                                color: cs.primary,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              _statusLabel(status),
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        (f['content'] ?? '').toString(),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: cs.onSurface,
                          height: 1.45,
                        ),
                      ),
                      if (reply.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                I18n.tr('feedback.admin_reply'),
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(
                                      color: cs.primary,
                                      fontWeight: FontWeight.w400,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                reply,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: cs.onSurface.withValues(
                                        alpha: 0.7,
                                      ),
                                      height: 1.45,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
