import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:duoyi/desktop_web/desktop_embedded_scope.dart';

import '../core/design_tokens.dart';
import '../core/feedback_ui_copy.dart';
import '../core/i18n.dart';
import '../providers/auth_provider.dart';
import '../services/account_local_data_cleaner.dart';
import '../services/api_client.dart';
import '../widgets/empty_state.dart';
import '../widgets/surface_components.dart';
import '../widgets/brand_background.dart'
    show BrandBackground, BrandRouteSurface, LocaleStatePreservingRoute;
import 'login_screen.dart';

Color _statusColor(BuildContext context, String value) {
  return switch (value) {
    'resolved' => DesignTokens.defaultSuccess,
    'closed' => Theme.of(context).colorScheme.onSurfaceVariant,
    'in_progress' => DesignTokens.defaultWarning,
    _ => Theme.of(context).colorScheme.primary,
  };
}

Color _resolveAccessibleForeground(
  Color background,
  Color preferred, {
  required bool isDark,
  double minContrast = 4.5,
}) {
  final effectivePreferred = Color.alphaBlend(preferred, background);
  if (appContrastRatio(background, effectivePreferred) >= minContrast) {
    return preferred;
  }
  final target = isDark ? Colors.white : const Color(0xFF111827);
  for (var t = 0.05; t <= 0.90; t += 0.05) {
    final candidate = Color.lerp(preferred, target, t)!;
    final effectiveCandidate = Color.alphaBlend(candidate, background);
    if (appContrastRatio(background, effectiveCandidate) >= minContrast) {
      return candidate;
    }
  }
  return appReadableForeground(background, preferred);
}

Color _resolveAccessibleErrorColor(
  BuildContext context,
  Color background,
  Color errorColor,
) {
  final surfaceStyle = appSurfaceStyleOf(context);
  final isLiquidGlass =
      surfaceStyle != null && (surfaceStyle.cardFillColor?.a ?? 1.0) < 0.8;
  final effectiveError = isLiquidGlass ? const Color(0xFFA23535) : errorColor;
  final effectiveBg = isLiquidGlass
      ? Color.alphaBlend(
          surfaceStyle.cardFillColor ?? background,
          Theme.of(context).scaffoldBackgroundColor,
        )
      : background;

  if (appContrastRatio(effectiveBg, effectiveError) >= 4.5) {
    return effectiveError;
  }
  const dark = Color(0xFF111827);
  for (var t = 0.05; t <= 0.60; t += 0.05) {
    final candidate = Color.lerp(effectiveError, dark, t)!;
    if (appContrastRatio(effectiveBg, candidate) >= 4.5) {
      return candidate;
    }
  }
  return appReadableForeground(effectiveBg, effectiveError);
}

Color _resolveSubmitFloatingLabelColor(
  BuildContext context,
  Color cardSurface,
) {
  final cs = Theme.of(context).colorScheme;
  final surfaceStyle = appSurfaceStyleOf(context);
  final isLiquidGlass =
      surfaceStyle != null && (surfaceStyle.cardFillColor?.a ?? 1.0) < 0.8;
  if (isLiquidGlass) {
    return const Color(0xFF0864CC);
  }
  if (appContrastRatio(cardSurface, cs.primary) >= 4.5) {
    return cs.primary;
  }
  const dark = Color(0xFF111827);
  for (var t = 0.05; t <= 0.60; t += 0.05) {
    final candidate = Color.lerp(cs.primary, dark, t)!;
    if (appContrastRatio(cardSurface, candidate) >= 4.5) {
      return candidate;
    }
  }
  return appReadableForeground(cardSurface, cs.primary);
}

Color _feedbackCardBackground(BuildContext context) {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  final isDark = theme.brightness == Brightness.dark;
  final surfaceStyle = appSurfaceStyleOf(context);
  final cardBackdrop = isDark ? cs.surface : theme.scaffoldBackgroundColor;
  return surfaceStyle?.cardFillColor != null
      ? Color.alphaBlend(surfaceStyle!.cardFillColor!, cardBackdrop)
      : cs.surface;
}

class _FeedbackLocaleText extends StatelessWidget {
  final String Function(AppLocale locale) copyBuilder;

  const _FeedbackLocaleText(this.copyBuilder);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, locale, _) => Text(copyBuilder(locale)),
    );
  }
}

Widget _wrapFeedbackScaffold(
  BuildContext context, {
  required Widget scaffold,
  required Color routeBackground,
  required bool isLiquidGlass,
}) {
  if (!isLiquidGlass) {
    return scaffold;
  }

  final hasBrandSurface =
      DesktopEmbeddedHostScope.isHosted(context) ||
      context.findAncestorWidgetOfExactType<BrandBackground>() != null ||
      context.findAncestorWidgetOfExactType<BrandRouteSurface>() != null;
  if (hasBrandSurface) {
    return scaffold;
  }
  return Material(
    color: routeBackground,
    child: BrandBackground(child: scaffold),
  );
}

class FeedbackScreen extends StatefulWidget
    implements LocaleStatePreservingRoute {
  final String initialCategory;

  const FeedbackScreen({super.key, this.initialCategory = 'feature'});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  static const int _pageSize = 10;

  final List<Map<String, dynamic>> _items = [];
  bool _loading = false;
  Object? _loadError;
  int _page = 1;
  int _totalPages = 1;
  int _total = 0;
  int _loadSerial = 0;

  bool _initialized = false;
  String? _currentUserId;
  String? _currentToken;
  int _currentAccountGeneration = 0;
  Route<void>? _activeDetailRoute;

  @override
  void initState() {
    super.initState();
    I18n.localeListenable.addListener(_handleLocaleChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.watch<AuthProvider>();
    final currentUserId = auth.state.userId;
    final currentToken = auth.state.token;
    final currentGeneration = AccountLocalDataCleaner.accountDataGeneration;
    if (_initialized) {
      if (_currentUserId != currentUserId ||
          _currentToken != currentToken ||
          _currentAccountGeneration != currentGeneration) {
        _currentUserId = currentUserId;
        _currentToken = currentToken;
        _currentAccountGeneration = currentGeneration;
        _onAccountChanged(auth);
      }
    } else {
      _initialized = true;
      _currentUserId = currentUserId;
      _currentToken = currentToken;
      _currentAccountGeneration = currentGeneration;
    }
  }

  @override
  void dispose() {
    I18n.localeListenable.removeListener(_handleLocaleChanged);
    _dismissActiveDetailRoute();
    super.dispose();
  }

  void _handleLocaleChanged() {
    if (mounted) setState(() {});
  }

  void _dismissActiveDetailRoute() {
    final route = _activeDetailRoute;
    _activeDetailRoute = null;
    if (route != null && route.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (route.isActive) {
          route.navigator?.removeRoute(route);
        }
      });
    }
  }

  void _onAccountChanged(AuthProvider auth) {
    _loadSerial++;
    _dismissActiveDetailRoute();
    setState(() {
      _items.clear();
      _page = 1;
      _totalPages = 1;
      _total = 0;
      _loadError = null;
      _loading = false;
    });
    if (auth.state.isLoggedIn) {
      _load(page: 1);
    }
  }

  String _categoryLabel(String value) => FeedbackUiCopy.categoryLabel(value);

  String _statusLabel(String value) => FeedbackUiCopy.statusLabel(value);

  Future<void> _load({int? page}) async {
    final auth = context.read<AuthProvider>();
    if (!auth.state.isLoggedIn) return;

    AuthSessionLease? lease;
    try {
      lease = auth.captureSessionLease();
    } catch (_) {
      return;
    }

    final originClient = auth.client;
    final originUserId = auth.state.userId;
    final originGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final loadSerial = ++_loadSerial;
    final nextPage = page ?? _page;

    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final path = '/api/feedback/me?page=$nextPage&page_size=$_pageSize';
      final raw = await originClient.getRaw(path);

      if (!mounted || loadSerial != _loadSerial) return;
      if (!auth.isSessionLeaseCurrent(lease) ||
          auth.state.userId != originUserId ||
          !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
            originGeneration,
          )) {
        return;
      }

      final res = raw is Map<String, dynamic> ? raw : <String, dynamic>{};
      final list = raw is List<dynamic>
          ? raw
          : (res['items'] as List<dynamic>? ?? const []);
      final rawItems = list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

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
      if (mounted &&
          loadSerial == _loadSerial &&
          auth.isSessionLeaseCurrent(lease) &&
          auth.state.userId == originUserId &&
          AccountLocalDataCleaner.isCurrentAccountDataGeneration(
            originGeneration,
          )) {
        setState(() => _loadError = e);
      }
    } catch (e) {
      if (mounted &&
          loadSerial == _loadSerial &&
          auth.isSessionLeaseCurrent(lease) &&
          auth.state.userId == originUserId &&
          AccountLocalDataCleaner.isCurrentAccountDataGeneration(
            originGeneration,
          )) {
        setState(() => _loadError = e);
      }
    } finally {
      if (mounted && loadSerial == _loadSerial) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openSubmit(String category) async {
    final auth = context.read<AuthProvider>();
    if (!auth.state.isLoggedIn) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      if (!mounted) return;
      if (!context.read<AuthProvider>().state.isLoggedIn) return;
    }
    final submitted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => FeedbackSubmitScreen(initialCategory: category),
      ),
    );
    if (submitted == true && mounted) {
      final currentAuth = context.read<AuthProvider>();
      if (currentAuth.state.isLoggedIn &&
          currentAuth.state.userId == _currentUserId &&
          AccountLocalDataCleaner.isCurrentAccountDataGeneration(
            _currentAccountGeneration,
          )) {
        await _load(page: 1);
      }
    }
  }

  Future<void> _showFeedbackDetail(Map<String, dynamic> item) async {
    final auth = context.read<AuthProvider>();
    final route = DialogRoute<void>(
      context: context,
      builder: (ctx) => _FeedbackDetailDialog(
        item: item,
        originUserId: auth.state.userId,
        originGeneration: AccountLocalDataCleaner.accountDataGeneration,
      ),
    );
    _activeDetailRoute = route;
    await Navigator.of(context).push(route);
    if (_activeDetailRoute == route) {
      _activeDetailRoute = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final loggedIn = auth.state.isLoggedIn;
    final cs = Theme.of(context).colorScheme;
    final routeBackground = Theme.of(context).brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;
    final surfaceStyle = appSurfaceStyleOf(context);
    final isLiquidGlass = surfaceStyle == AppSurfaceStyle.liquidGlass;
    final errorMessage = _loadError != null
        ? FeedbackUiCopy.formatError(_loadError)
        : null;

    final scaffold = Scaffold(
      backgroundColor: isLiquidGlass ? Colors.transparent : routeBackground,
      appBar: AppBar(
        title: Text(FeedbackUiCopy.screenTitle()),
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
        backgroundColor: routeBackground.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('feedback_submit_fab'),
        heroTag: 'feedback_submit_fab',
        onPressed: () => _openSubmit(widget.initialCategory),
        icon: const Icon(Icons.add_comment_outlined),
        label: Text(FeedbackUiCopy.submitButton()),
      ),
      body: AppSecondaryControlTheme(
        child: RefreshIndicator(
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
                            title:
                                FeedbackUiCopy.historySectionTitle(), // title: '反馈记录'
                            padding: EdgeInsets.zero,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            FeedbackUiCopy.historySummary(
                              total: _total,
                              page: _page,
                              totalPages: _totalPages,
                              loggedIn: loggedIn,
                            ),
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
              if (!loggedIn)
                EmptyState(
                  icon: Icons.login_outlined,
                  message: FeedbackUiCopy.loginRecordsRequired(),
                  actionLabel: FeedbackUiCopy.loginSubmitPrefix(
                    widget.initialCategory,
                  ),
                  onAction: () => _openSubmit(widget.initialCategory),
                )
              else if (_loading && _items.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (errorMessage != null && _items.isEmpty)
                EmptyState(
                  icon: Icons.error_outline,
                  message: errorMessage,
                  actionLabel: FeedbackUiCopy.refresh(),
                  onAction: () => _load(page: _page),
                )
              else if (_items.isEmpty)
                EmptyState(
                  icon: Icons.feedback_outlined,
                  message: FeedbackUiCopy.emptyHistory(),
                  actionLabel: FeedbackUiCopy.submitButton(),
                  onAction: () => _openSubmit(widget.initialCategory),
                )
              else ...[
                ..._items.map((item) {
                  final recordId = (item['id'] ?? item['created_at'] ?? '')
                      .toString();
                  return _FeedbackRecordSwipeActions(
                    key: ValueKey('feedback_record_swipe_$recordId'),
                    recordId: recordId,
                    onDetail: () => _showFeedbackDetail(item),
                    child: _FeedbackRecordCard(
                      item: item,
                      categoryLabel: _categoryLabel,
                      statusLabel: _statusLabel,
                      statusColor: (status) => _statusColor(context, status),
                      onTap: () => _showFeedbackDetail(item),
                    ),
                  );
                }),
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
      ),
    );

    return _wrapFeedbackScaffold(
      context,
      scaffold: scaffold,
      routeBackground: routeBackground,
      isLiquidGlass: isLiquidGlass,
    );
  }
}

class _FeedbackDetailDialog extends StatefulWidget {
  final Map<String, dynamic> item;
  final String? originUserId;
  final int originGeneration;

  const _FeedbackDetailDialog({
    required this.item,
    required this.originUserId,
    required this.originGeneration,
  });

  @override
  State<_FeedbackDetailDialog> createState() => _FeedbackDetailDialogState();
}

class _FeedbackDetailDialogState extends State<_FeedbackDetailDialog> {
  @override
  void initState() {
    super.initState();
    I18n.localeListenable.addListener(_handleLocaleChanged);
  }

  @override
  void dispose() {
    I18n.localeListenable.removeListener(_handleLocaleChanged);
    super.dispose();
  }

  void _handleLocaleChanged() {
    if (mounted) setState(() {});
  }

  void _safeClose() {
    final route = ModalRoute.of(context);
    if (route != null && route.isActive) {
      route.navigator?.removeRoute(route);
    }
  }

  void _closeDialogByUser() {
    final route = ModalRoute.of(context);
    if (route != null && route.isActive) {
      if (route.isCurrent) {
        Navigator.of(context).pop();
      } else {
        route.navigator?.removeRoute(route);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final currentGeneration = AccountLocalDataCleaner.accountDataGeneration;
    if (auth.state.userId != widget.originUserId ||
        currentGeneration != widget.originGeneration) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _safeClose();
      });
      return const SizedBox.shrink();
    }

    final item = widget.item;
    final category = (item['category'] ?? 'feature').toString();
    final status = (item['status'] ?? 'open').toString();
    final content = (item['content'] ?? '').toString();
    final reply = (item['admin_reply'] ?? '').toString();
    final createdAt = (item['created_at'] ?? '').toString();
    final updatedAt = (item['updated_at'] ?? '').toString();
    final cs = Theme.of(context).colorScheme;

    return AppDialog(
      maxWidth: 620,
      icon: const Icon(Icons.feedback_outlined),
      title: Text(FeedbackUiCopy.detailTitle()),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540, maxHeight: 520),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _FeedbackDetailBadge(
                    label: FeedbackUiCopy.categoryLabel(category),
                    icon: Icons.category_outlined,
                    color: cs.primary,
                  ),
                  _FeedbackDetailBadge(
                    label: FeedbackUiCopy.statusLabel(status),
                    icon: Icons.radio_button_checked,
                    color: _statusColor(context, status),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (createdAt.isNotEmpty)
                _FeedbackDetailField(
                  label: FeedbackUiCopy.detailSubmittedAt(),
                  value: createdAt,
                ),
              if (updatedAt.isNotEmpty)
                _FeedbackDetailField(
                  label: FeedbackUiCopy.detailUpdatedAt(),
                  value: updatedAt,
                ),
              _FeedbackDetailField(
                label: FeedbackUiCopy.detailContent(),
                value: content.trim().isEmpty
                    ? FeedbackUiCopy.detailEmptyContent()
                    : content,
                multiline: true,
              ),
              if (reply.trim().isNotEmpty)
                _FeedbackDetailField(
                  label: FeedbackUiCopy.detailReply(),
                  value: reply,
                  multiline: true,
                  tint: cs.primary,
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _closeDialogByUser,
          child: Text(FeedbackUiCopy.actionClose()),
        ),
      ],
    );
  }
}

class _FeedbackDetailBadge extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _FeedbackDetailBadge({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return AppStatusBadge(label: label, color: color, icon: icon);
  }
}

class _FeedbackDetailField extends StatelessWidget {
  final String label;
  final String value;
  final bool multiline;
  final Color? tint;

  const _FeedbackDetailField({
    required this.label,
    required this.value,
    this.multiline = false,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final accent = tint ?? cs.outlineVariant;
    final dialogBg = theme.dialogTheme.backgroundColor ?? cs.surface;
    final fieldBg = Color.alphaBlend(
      accent.withValues(alpha: tint == null ? 0.06 : 0.08),
      dialogBg,
    );
    final labelColor = _resolveAccessibleForeground(
      fieldBg,
      cs.onSurface.withValues(alpha: 0.75),
      isDark: isDark,
    );
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: tint == null ? 0.06 : 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: accent.withValues(alpha: tint == null ? 0.10 : 0.14),
          width: 0.45,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: appSecondaryControlLabelStyle(
              context,
            ).copyWith(color: labelColor),
          ),
          const SizedBox(height: 4),
          SelectableText(
            value,
            style:
                (multiline
                        ? theme.textTheme.bodyMedium
                        : theme.textTheme.bodySmall)
                    ?.copyWith(
                      color: cs.onSurface.withValues(
                        alpha: multiline ? 0.84 : 0.70,
                      ),
                      height: multiline ? 1.38 : 1.25,
                      fontWeight: FontWeight.normal,
                    ),
          ),
        ],
      ),
    );
  }
}

enum _FeedbackSubmitErrorType {
  emptyContent,
  accountChanged,
  loginRequired,
  transitionInProgress,
}

class FeedbackSubmitScreen extends StatefulWidget {
  final String initialCategory;

  const FeedbackSubmitScreen({super.key, this.initialCategory = 'feature'});

  @override
  State<FeedbackSubmitScreen> createState() => _FeedbackSubmitScreenState();
}

class _FeedbackSubmitScreenState extends State<FeedbackSubmitScreen> {
  late String _category;
  final _contentCtrl = TextEditingController();
  bool _submitting = false;

  _FeedbackSubmitErrorType? _submitErrorType;
  Object? _rawSubmitError;

  late final AuthProvider _auth;
  late final bool _originIsLoggedIn;
  late final String? _originUserId;
  late final int _originGeneration;
  late final ApiClient _originClient;
  AuthSessionLease? _originSessionLease;
  bool _leaseCaptureFailed = false;

  @override
  void initState() {
    super.initState();
    _category = normalizeFeedbackCategory(widget.initialCategory);
    I18n.localeListenable.addListener(_handleLocaleChanged);
    _auth = context.read<AuthProvider>();
    _originIsLoggedIn = _auth.state.isLoggedIn;
    _originUserId = _auth.state.userId;
    _originGeneration = AccountLocalDataCleaner.accountDataGeneration;
    _originClient = _auth.client;

    if (_originIsLoggedIn) {
      try {
        _originSessionLease = _auth.captureSessionLease();
      } catch (_) {
        _originSessionLease = null;
        _leaseCaptureFailed = true;
      }
    } else {
      _originSessionLease = null;
    }
  }

  @override
  void dispose() {
    I18n.localeListenable.removeListener(_handleLocaleChanged);
    _contentCtrl.dispose();
    super.dispose();
  }

  void _handleLocaleChanged() {
    if (mounted) setState(() {});
  }

  bool _isCurrentSession() {
    if (!mounted) return false;
    if (!_originIsLoggedIn ||
        _originSessionLease == null ||
        _leaseCaptureFailed) {
      return false;
    }
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
      _originGeneration,
    )) {
      return false;
    }
    final currentAuth = context.read<AuthProvider>();
    if (!identical(currentAuth, _auth)) return false;
    if (!currentAuth.state.isLoggedIn) return false;
    if (currentAuth.state.userId != _originUserId) return false;
    if (!currentAuth.isSessionLeaseCurrent(_originSessionLease!)) {
      return false;
    }
    return true;
  }

  Future<void> _submit() async {
    if (_submitting) return;

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final ownerRoute = ModalRoute.of(context);

    if (_leaseCaptureFailed) {
      setState(() {
        _submitErrorType = _FeedbackSubmitErrorType.transitionInProgress;
        _rawSubmitError = null;
      });
      return;
    }

    if (!_originIsLoggedIn || _originSessionLease == null) {
      setState(() {
        _submitErrorType = _FeedbackSubmitErrorType.loginRequired;
        _rawSubmitError = null;
      });
      return;
    }

    if (!_isCurrentSession()) {
      setState(() {
        _submitErrorType = _FeedbackSubmitErrorType.accountChanged;
        _rawSubmitError = null;
      });
      return;
    }

    final content = _contentCtrl.text.trim();
    if (content.isEmpty) {
      setState(() {
        _submitErrorType = _FeedbackSubmitErrorType.emptyContent;
        _rawSubmitError = null;
      });
      return;
    }

    setState(() {
      _submitting = true;
      _submitErrorType = null;
      _rawSubmitError = null;
    });

    try {
      await _originClient.post('/api/feedback', {
        'category': _category,
        'content': content,
      });

      if (!mounted || (ownerRoute != null && !ownerRoute.isCurrent)) return;
      if (!_isCurrentSession()) return;

      if (navigator.canPop()) {
        navigator.pop(true);
      }
      messenger?.showSnackBar(
        SnackBar(
          content: _FeedbackLocaleText(
            (locale) => FeedbackUiCopy.submitted(locale),
          ),
        ),
      );
    } on ApiException catch (e) {
      if (mounted && _isCurrentSession()) {
        setState(() {
          _submitErrorType = null;
          _rawSubmitError = e;
        });
      }
    } catch (e) {
      if (mounted && _isCurrentSession()) {
        setState(() {
          _submitErrorType = null;
          _rawSubmitError = e;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  String? _getSubmitErrorMessage() {
    if (_leaseCaptureFailed) {
      return FeedbackUiCopy.accountTransitionInProgress();
    }
    if (_submitErrorType != null) {
      return switch (_submitErrorType!) {
        _FeedbackSubmitErrorType.emptyContent => FeedbackUiCopy.contentEmpty(),
        _FeedbackSubmitErrorType.accountChanged =>
          FeedbackUiCopy.accountChangedReopen(),
        _FeedbackSubmitErrorType.loginRequired =>
          FeedbackUiCopy.loginRequiredReopen(),
        _FeedbackSubmitErrorType.transitionInProgress =>
          FeedbackUiCopy.accountTransitionInProgress(),
      };
    }
    if (_rawSubmitError != null) {
      return FeedbackUiCopy.formatError(_rawSubmitError);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final loggedIn = auth.state.isLoggedIn;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = _feedbackCardBackground(context);
    final routeBackground = isDark
        ? cs.surface
        : cs.surfaceContainerLowest;
    final surfaceStyle = appSurfaceStyleOf(context);
    final isLiquidGlass = surfaceStyle == AppSurfaceStyle.liquidGlass;
    final errorMessage = _getSubmitErrorMessage();
    final canSubmit = loggedIn && !_submitting && !_leaseCaptureFailed;
    final textScaler = MediaQuery.textScalerOf(context);
    final labelStyle = appSecondaryControlLabelStyle(context);
    final floatingColor = _resolveSubmitFloatingLabelColor(
      context,
      cardBg,
    );
    final helperColor = _resolveAccessibleForeground(
      cardBg,
      cs.onSurfaceVariant,
      isDark: isDark,
    );
    final topPadding = math.max(14.0, textScaler.scale(18.0));
    final bottomPadding = math.max(10.0, textScaler.scale(12.0));

    final scaffold = Scaffold(
      backgroundColor: isLiquidGlass ? Colors.transparent : routeBackground,
      appBar: AppBar(
        title: Text(FeedbackUiCopy.submitTitle()),
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
        backgroundColor: routeBackground.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
      ),
      body: AppSecondaryControlTheme(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: [
            AppSurfaceCard(
              key: const ValueKey('feedback_submit_page_card'),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppSectionHeader(
                    title: FeedbackUiCopy.submitHeaderTitle(),
                    subtitle: loggedIn
                        ? FeedbackUiCopy.submitHeaderSubtitle()
                        : FeedbackUiCopy.loginSubmitRequired(),
                    padding: EdgeInsets.zero,
                    wrapText: true,
                  ),
                  const SizedBox(height: 12),
                  _FeedbackCategoryMenu(
                    selected: _category,
                    enabled: loggedIn && !_submitting,
                    labelFor: (cat, [loc]) =>
                        FeedbackUiCopy.categoryLabel(cat, loc),
                    onSelected: (value) => setState(() {
                      _category = normalizeFeedbackCategory(value);
                      _submitErrorType = null;
                      _rawSubmitError = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('feedback_submit_content'),
                    controller: _contentCtrl,
                    enabled: loggedIn && !_submitting,
                    minLines: 5,
                    maxLines: 9,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.fromLTRB(
                        10,
                        topPadding,
                        10,
                        bottomPadding,
                      ),
                      label: Text(FeedbackUiCopy.contentLabel(_category)),
                      floatingLabelStyle: labelStyle.copyWith(
                        color: floatingColor,
                        fontWeight: FontWeight.normal,
                      ),
                      helper: Text(
                        FeedbackUiCopy.categoryHelp(_category),
                        style: theme.inputDecorationTheme.helperStyle ??
                            labelStyle.copyWith(color: helperColor),
                      ),
                      alignLabelWithHint: true,
                    ),
                  ),
                  if (errorMessage != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      errorMessage,
                      style: TextStyle(
                        color: _resolveAccessibleErrorColor(
                          context,
                          cardBg,
                          cs.error,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      key: const ValueKey('feedback_submit_page_button'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 44),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                      onPressed: canSubmit ? _submit : null,
                      icon: _submitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_outlined),
                      label: Text(
                        _submitting
                            ? FeedbackUiCopy.submitting()
                            : FeedbackUiCopy.submitButton(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return _wrapFeedbackScaffold(
      context,
      scaffold: scaffold,
      routeBackground: routeBackground,
      isLiquidGlass: isLiquidGlass,
    );
  }
}

class _FeedbackCategoryMenu extends StatelessWidget {
  final String selected;
  final bool enabled;
  final String Function(String, [AppLocale?]) labelFor;
  final ValueChanged<String> onSelected;

  const _FeedbackCategoryMenu({
    required this.selected,
    this.enabled = true,
    required this.labelFor,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final selectedBg = enabled
        ? cs.primary.withValues(alpha: 0.1)
        : cs.onSurface.withValues(alpha: 0.04);
    final selectedBorder = enabled
        ? cs.primary.withValues(alpha: 0.28)
        : cs.outlineVariant.withValues(alpha: 0.14);
    final selectedFg = enabled
        ? cs.onSurface
        : cs.onSurface.withValues(alpha: 0.38);
    final iconColor = enabled
        ? cs.primary
        : cs.onSurface.withValues(alpha: 0.38);

    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, locale, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final textScale = MediaQuery.textScalerOf(context).scale(1.0);
            final isNarrow = constraints.maxWidth < 360 || textScale > 1.2;

            final theme = Theme.of(context);
            final isDark = theme.brightness == Brightness.dark;
            final cardBg = _feedbackCardBackground(context);
            final categoryLabelColor = _resolveAccessibleForeground(
              cardBg,
              cs.onSurface.withValues(alpha: enabled ? 0.75 : 0.38),
              isDark: isDark,
            );

            final labelWidget = Text(
              FeedbackUiCopy.categoryMenuLabel(locale),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: categoryLabelColor,
              ),
            );

            final buttonWidget = Listener(
              onPointerDown: enabled
                  ? (_) {
                      FocusScope.of(context, createDependency: false).unfocus();
                      FocusManager.instance.primaryFocus?.unfocus();
                    }
                  : null,
              child: PopupMenuButton<String>(
                enabled: enabled,
                tooltip: FeedbackUiCopy.categoryLabelTooltip(locale),
                initialValue: selected,
                onSelected: onSelected,
                itemBuilder: (context) => [
                  for (final category in const ['feature', 'bug', 'wish'])
                    PopupMenuItem<String>(
                      value: category,
                      child: ValueListenableBuilder<AppLocale>(
                        valueListenable: I18n.localeListenable,
                        builder: (context, currentLocale, _) {
                          return Row(
                            children: [
                              Expanded(
                                child: AppSecondaryMenuText(
                                  labelFor(category, currentLocale),
                                ),
                              ),
                              if (selected == category)
                                Icon(Icons.check, size: 16, color: cs.primary),
                            ],
                          );
                        },
                      ),
                    ),
                ],
                child: Container(
                  constraints: BoxConstraints(
                    minHeight: 44,
                    maxWidth: constraints.maxWidth,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: selectedBg,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: selectedBorder, width: 0.45),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          labelFor(selected, locale),
                          style: appSecondaryControlTextStyle(context).copyWith(
                            color: selectedFg,
                            fontWeight: FontWeight.normal,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_drop_down, color: iconColor, size: 18),
                    ],
                  ),
                ),
              ),
            );

            if (isNarrow) {
              return Column(
                key: const ValueKey('feedback_three_level_menu'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  labelWidget,
                  const SizedBox(height: 6),
                  buttonWidget,
                ],
              );
            }

            return Row(
              key: const ValueKey('feedback_three_level_menu'),
              children: [labelWidget, const SizedBox(width: 8), buttonWidget],
            );
          },
        );
      },
    );
  }
}

class _FeedbackRecordCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final String Function(String) categoryLabel;
  final String Function(String) statusLabel;
  final Color Function(String) statusColor;
  final VoidCallback onTap;

  const _FeedbackRecordCard({
    required this.item,
    required this.categoryLabel,
    required this.statusLabel,
    required this.statusColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final category = (item['category'] ?? 'feature').toString();
    final status = (item['status'] ?? 'open').toString();
    final content = (item['content'] ?? '').toString();
    final reply = (item['admin_reply'] ?? '').toString();
    final createdAt = (item['created_at'] ?? '').toString();
    final color = statusColor(status);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = _feedbackCardBackground(context);
    final timestampColor = _resolveAccessibleForeground(
      cardBg,
      cs.onSurface.withValues(alpha: 0.75),
      isDark: isDark,
    );
    final replyBoxBg = Color.alphaBlend(
      cs.primaryContainer.withValues(alpha: 0.42),
      cardBg,
    );
    final replyHeadingColor = appReadableForeground(
      replyBoxBg,
      cs.onSurface,
    );
    return AppSurfaceCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.zero,
      child: InkWell(
        key: const ValueKey('feedback_record_card_tap_target'),
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      categoryLabel(category),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.normal,
                      ),
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
                    color: timestampColor,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(content, maxLines: 4, overflow: TextOverflow.ellipsis),
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
                        FeedbackUiCopy.detailReply(),
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: replyHeadingColor,
                              fontWeight: FontWeight.normal,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(reply, maxLines: 3, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FeedbackRecordSwipeActions extends StatefulWidget {
  final String recordId;
  final Widget child;
  final VoidCallback onDetail;

  const _FeedbackRecordSwipeActions({
    super.key,
    required this.recordId,
    required this.child,
    required this.onDetail,
  });

  @override
  State<_FeedbackRecordSwipeActions> createState() =>
      _FeedbackRecordSwipeActionsState();
}

class _FeedbackRecordSwipeActionsState
    extends State<_FeedbackRecordSwipeActions> {
  static const double _actionRailWidth = 64;
  static const double _dragOpenThreshold = 40;
  double _dragDistance = 0;
  bool _open = false;

  @override
  void didUpdateWidget(covariant _FeedbackRecordSwipeActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.recordId != oldWidget.recordId) {
      _dragDistance = 0;
      _open = false;
    }
  }

  void _setOpen(bool value) {
    if (_open == value) return;
    setState(() => _open = value);
  }

  void _showDetail() {
    _setOpen(false);
    widget.onDetail();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ClipRect(
      child: GestureDetector(
        key: const ValueKey('feedback_record_swipe_actions'),
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) => _dragDistance = 0,
        onHorizontalDragUpdate: (details) {
          _dragDistance += details.delta.dx;
          if (_dragDistance <= -_dragOpenThreshold) _setOpen(true);
          if (_dragDistance >= _dragOpenThreshold) _setOpen(false);
        },
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity < -120) _setOpen(true);
          if (velocity > 120) _setOpen(false);
          _dragDistance = 0;
        },
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            if (_open)
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.only(right: 4, bottom: 8),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withValues(
                          alpha: 0.92,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: cs.outlineVariant.withValues(alpha: 0.18),
                          width: 0.45,
                        ),
                      ),
                      child: SizedBox(
                        width: _actionRailWidth,
                        height: 48,
                        child: Center(
                          child: IconButton(
                            key: const ValueKey(
                              'feedback_record_detail_action',
                            ),
                            tooltip: FeedbackUiCopy.detailTooltip(),
                            constraints: const BoxConstraints.tightFor(
                              width: 44,
                              height: 44,
                            ),
                            padding: EdgeInsets.zero,
                            icon: Icon(
                              Icons.visibility_outlined,
                              color: cs.primary,
                              size: 20,
                            ),
                            onPressed: _showDetail,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              transform: Matrix4.translationValues(
                _open ? -_actionRailWidth : 0,
                0,
                0,
              ),
              child: widget.child,
            ),
            if (_open)
              Positioned.fill(
                right: _actionRailWidth,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => _setOpen(false),
                ),
              ),
          ],
        ),
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
    final pageLabel = Text(
      FeedbackUiCopy.paginationPage(page, totalPages),
      textAlign: TextAlign.center,
      style: appSecondaryControlLabelStyle(
        context,
      ).copyWith(fontWeight: FontWeight.w400),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 360;
        final controls = [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: loading ? null : onPrevious,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              ),
              icon: const Icon(Icons.chevron_left, size: 18),
              label: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(FeedbackUiCopy.paginationPrevious()),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: loading ? null : onNext,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              ),
              icon: const Icon(Icons.chevron_right, size: 18),
              label: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(FeedbackUiCopy.paginationNext()),
              ),
            ),
          ),
        ];
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              pageLabel,
              const SizedBox(height: 8),
              Row(children: controls),
            ],
          );
        }
        return Row(
          children: [
            controls[0],
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: pageLabel,
            ),
            controls[2],
          ],
        );
      },
    );
  }
}

String normalizeFeedbackCategory(String value) =>
    FeedbackUiCopy.normalizeCategory(value);

String feedbackCategoryLabel(String value, [AppLocale? locale]) =>
    FeedbackUiCopy.categoryLabel(value, locale);

String feedbackCategoryHelp(String value, [AppLocale? locale]) =>
    FeedbackUiCopy.categoryHelp(value, locale);
