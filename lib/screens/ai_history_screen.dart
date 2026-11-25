import 'dart:math' as math;

import '../widgets/app_date_format.dart';
import '../core/i18n_date_format.dart';
import 'package:flutter/material.dart';
import '../core/i18n.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/ai_service.dart';
import '../widgets/empty_state.dart';
import '../core/design_tokens.dart';
import '../widgets/surface_components.dart';
import '../widgets/controller_dialog.dart';
import 'package:duoyi/desktop_web/desktop_embedded_scope.dart';

import '../widgets/brand_background.dart'
    show BrandBackground, BrandRouteSurface, LocaleStatePreservingRoute;
import '../services/settings_action_origin.dart';
import '../services/account_local_data_cleaner.dart';
import '../providers/auth_provider.dart';
import '../core/account_ui_copy.dart';

class _HistoryActionOrigin {
  _HistoryActionOrigin(BuildContext context, AiService ai)
    : settings = SettingsActionOrigin(context),
      historyGeneration = ai.historyGeneration;

  final SettingsActionOrigin settings;
  final int historyGeneration;
}

/// AI 周回顾历史：本地持久化最近 50 条。
class AiHistoryScreen extends StatefulWidget
    implements LocaleStatePreservingRoute {
  const AiHistoryScreen({super.key});

  @override
  State<AiHistoryScreen> createState() => _AiHistoryScreenState();
}

class _AiHistoryScreenState extends State<AiHistoryScreen> {
  final Set<String> _expandedReviewIds = <String>{};
  AiService? _owner;
  AuthProvider? _authOwner;
  int? _historyGeneration;
  int? _accountGeneration;
  int? _sessionGeneration;

  @override
  void initState() {
    super.initState();
    I18n.localeListenable.addListener(_localeChanged);
  }

  void _localeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ai = context.watch<AiService>();
    final auth = context.watch<AuthProvider?>();
    final generation = AccountLocalDataCleaner.accountDataGeneration;
    if (!identical(_owner, ai) ||
        !identical(_authOwner, auth) ||
        _historyGeneration != ai.historyGeneration ||
        _accountGeneration != generation ||
        _sessionGeneration != auth?.sessionGeneration) {
      _expandedReviewIds.clear();
    }
    _owner = ai;
    _authOwner = auth;
    _historyGeneration = ai.historyGeneration;
    _accountGeneration = generation;
    _sessionGeneration = auth?.sessionGeneration;
  }

  @override
  void dispose() {
    I18n.localeListenable.removeListener(_localeChanged);
    super.dispose();
  }

  bool _isCurrent(
    AiService ai,
    _HistoryActionOrigin origin, {
    bool checkRoute = true,
  }) =>
      mounted &&
      identical(context.read<AiService>(), ai) &&
      ai.historyGeneration == origin.historyGeneration &&
      origin.settings.isCurrent(checkRoute: checkRoute);

  Widget _liveText(String key) => ValueListenableBuilder<AppLocale>(
    valueListenable: I18n.localeListenable,
    builder: (_, _, _) => Text(I18n.tr(key)),
  );

  Future<void> _perform(
    AiService ai,
    _HistoryActionOrigin origin,
    Future<void> Function() action, {
    VoidCallback? retry,
  }) async {
    if (!_isCurrent(ai, origin)) return;
    try {
      await action();
    } on AiReviewDiscardedException {
      // The service/account boundary invalidated the operation.
    } catch (error) {
      if (!mounted || !_isCurrent(ai, origin)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: ValueListenableBuilder<AppLocale>(
            valueListenable: I18n.localeListenable,
            builder: (_, _, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AccountUiCopy.formatError(error)),
                if (retry != null)
                  TextButton(
                    onPressed: () {
                      if (!_isCurrent(ai, origin)) return;
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      retry();
                    },
                    child: Text(AccountUiCopy.actionRetry),
                  ),
              ],
            ),
          ),
        ),
      );
    }
  }

  Future<void> _confirmClear(AiService ai, _HistoryActionOrigin origin) async {
    if (!_isCurrent(ai, origin)) return;
    ModalRoute<dynamic>? dialogRoute;
    final ok = await showControllerDialog<bool>(
      context: context,
      controllers: const [],
      builder: (ctx) {
        dialogRoute = ModalRoute.of(ctx);
        return ValueListenableBuilder<AppLocale>(
          valueListenable: I18n.localeListenable,
          builder: (_, _, _) => AppDialog(
            title: Text(I18n.tr('ai_history.clear.title')),
            icon: const Icon(Icons.delete_sweep_outlined),
            content: Text(I18n.tr('ai_history.clear.content')),
            actions: [
              TextButton(
                onPressed: () {
                  if (dialogRoute?.isCurrent == true) Navigator.pop(ctx, false);
                },
                child: Text(I18n.tr('action.cancel')),
              ),
              FilledButton(
                onPressed: () {
                  if (_isCurrent(ai, origin, checkRoute: false) &&
                      dialogRoute?.isActive == true &&
                      dialogRoute?.isCurrent == true) {
                    Navigator.pop(ctx, true);
                  }
                },
                child: Text(I18n.tr('ai_history.clear.action')),
              ),
            ],
          ),
        );
      },
    );
    await dialogRoute?.completed;
    if (ok != true || !_isCurrent(ai, origin)) return;
    await _perform(
      ai,
      origin,
      ai.clearReviewHistory,
      retry: () => _confirmClear(ai, origin),
    );
  }

  Future<void> _showEntryMenu(
    BuildContext buttonContext,
    AiService ai,
    AiReviewEntry entry,
    _HistoryActionOrigin origin,
  ) async {
    bool entryCurrent() =>
        _isCurrent(ai, origin) &&
        ai.reviewHistory.any((item) => identical(item, entry));
    if (!entryCurrent()) return;
    final button = buttonContext.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(buttonContext).overlay!.context.findRenderObject()!
            as RenderBox;
    final rect = Rect.fromPoints(
      button.localToGlobal(Offset.zero, ancestor: overlay),
      button.localToGlobal(
        button.size.bottomRight(Offset.zero),
        ancestor: overlay,
      ),
    );
    ModalRoute<dynamic>? menuRoute;
    final selected = await showMenu<String>(
      context: buttonContext,
      position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
      items: [
        for (final value in ['copy', 'delete'])
          PopupMenuItem(
            value: value,
            child: ValueListenableBuilder<AppLocale>(
              valueListenable: I18n.localeListenable,
              builder: (ctx, _, _) {
                menuRoute = ModalRoute.of(ctx);
                return Text(
                  I18n.tr('ai_history.$value'),
                  style: value == 'delete'
                      ? TextStyle(color: Theme.of(ctx).colorScheme.error)
                      : null,
                );
              },
            ),
          ),
      ],
    );
    await menuRoute?.completed;
    if (!entryCurrent()) return;
    if (selected == 'copy') {
      await _perform(ai, origin, () async {
        if (!entryCurrent()) return;
        await Clipboard.setData(ClipboardData(text: entry.content));
        if (!mounted || !_isCurrent(ai, origin)) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: _liveText('ai_history.copy.done')));
      });
    } else if (selected == 'delete') {
      Future<void> remove() async {
        // A failed write can remove the in-memory entry. Retrying its original
        // deletion is safe unless the ID has since been reused by another item.
        if (ai.reviewHistory.any(
          (item) => item.id == entry.id && !identical(item, entry),
        )) {
          return;
        }
        await ai.deleteReview(entry.id);
      }

      Future<void> delete() =>
          _perform(ai, origin, remove, retry: () => delete());
      await delete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final datePattern = AppDateFormat.patternOf(context);
    final ai = context.watch<AiService>();
    final origin = _HistoryActionOrigin(context, ai);
    final items = ai.reviewHistory;

    final textScaler = MediaQuery.textScalerOf(context);
    final titleStyle = Theme.of(context).appBarTheme.titleTextStyle ??
        Theme.of(context).textTheme.titleLarge ??
        const TextStyle(fontSize: 16.0);
    final titleSpacing = Theme.of(context).appBarTheme.titleSpacing ??
        NavigationToolbar.kMiddleSpacing;
    final hasLeading =
        ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
    final leadingWidth = hasLeading
        ? (Theme.of(context).appBarTheme.leadingWidth ?? kToolbarHeight)
        : 0.0;
    final actionsWidth = items.isNotEmpty ? 48.0 : 0.0;
    final occupiedTitleWidth =
        leadingWidth + actionsWidth + (titleSpacing * 2.0);
    final availableTitleWidth = math.max(
      0.0,
      MediaQuery.sizeOf(context).width - occupiedTitleWidth,
    );
    final titlePainter = TextPainter(
      text: TextSpan(text: I18n.tr('ai_history.title'), style: titleStyle),
      textDirection: Directionality.of(context),
      textScaler: textScaler.clamp(maxScaleFactor: 1.34),
    )..layout(maxWidth: availableTitleWidth);
    final titleLineCount = titlePainter.computeLineMetrics().length;
    final titleHeight = titlePainter.height;
    titlePainter.dispose();

    final baseToolbarHeight =
        Theme.of(context).appBarTheme.toolbarHeight ?? kToolbarHeight;
    final effectiveToolbarHeight = titleLineCount > 1
        ? math.max(baseToolbarHeight, titleHeight + 16.0)
        : baseToolbarHeight;
    final routeBackground = Theme.of(context).scaffoldBackgroundColor;
    final surfaceStyle = appSurfaceStyleOf(context);
    final isLiquidGlass = surfaceStyle == AppSurfaceStyle.liquidGlass;

    final scaffold = Scaffold(
      backgroundColor: isLiquidGlass ? Colors.transparent : routeBackground,
      appBar: AppBar(
        title: Text(
          I18n.tr('ai_history.title'),
          softWrap: true,
          overflow: TextOverflow.visible,
        ),
        toolbarHeight: effectiveToolbarHeight,
        actions: [
          if (items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: I18n.tr('ai_history.clear.tooltip'),
              onPressed: () => _confirmClear(ai, origin),
            ),
        ],
      ),
      body: items.isEmpty
          ? EmptyState(
              icon: Icons.auto_awesome,
              message: I18n.tr('ai_history.empty'),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              separatorBuilder: (context, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final e = items[i];
                final theme = Theme.of(context);
                final cs = theme.colorScheme;
                final createdAt = I18nDateFormat.fullDateTime(
                  e.createdAt,
                  pattern: datePattern,
                );
                final expanded = _expandedReviewIds.contains(e.id);
                return AppSurfaceCard(
                  padding: const EdgeInsets.all(14),
                  child: Padding(
                    padding: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.auto_awesome,
                              size: 18,
                              color: cs.primary,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                createdAt,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurface.withValues(alpha: 0.68),
                                  fontWeight: FontWeight.normal,
                                ),
                              ),
                            ),
                            IconButton(
                              key: ValueKey('ai_history_toggle_${e.id}'),
                              tooltip: I18n.tr(
                                expanded
                                    ? 'mine.ai.collapse'
                                    : 'mine.ai.expand',
                              ),
                              visualDensity: VisualDensity.standard,
                              constraints: const BoxConstraints(
                                minWidth: 44,
                                minHeight: 44,
                              ),
                              iconSize: 18,
                              onPressed: () {
                                if (!_isCurrent(ai, origin)) return;
                                setState(() {
                                  if (expanded) {
                                    _expandedReviewIds.remove(e.id);
                                  } else {
                                    _expandedReviewIds.add(e.id);
                                  }
                                });
                              },
                              icon: Icon(
                                expanded
                                    ? Icons.keyboard_arrow_up
                                    : Icons.keyboard_arrow_down,
                              ),
                            ),
                            Builder(
                              builder: (buttonContext) => IconButton(
                                key: ValueKey('ai_history_menu_${e.id}'),
                                iconSize: 18,
                                visualDensity: VisualDensity.standard,
                                constraints: const BoxConstraints(
                                  minWidth: 44,
                                  minHeight: 44,
                                ),
                                tooltip: MaterialLocalizations.of(
                                  context,
                                ).showMenuTooltip,
                                icon: const Icon(Icons.more_vert),
                                onPressed: () => _showEntryMenu(
                                  buttonContext,
                                  ai,
                                  e,
                                  origin,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (e.model.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          AppStatusBadge(
                            label: e.model,
                            color: cs.primary,
                            icon: Icons.memory_outlined,
                            maxWidth: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          e.displaySummary,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurface.withValues(alpha: 0.68),
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                        ClipRect(
                          key: ValueKey('ai_history_content_${e.id}'),
                          child: AnimatedSize(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOutCubic,
                            child: expanded
                                ? Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      e.content,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: cs.onSurface,
                                            height: 1.62,
                                          ),
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );

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
}
