import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/i18n.dart';
import '../core/i18n_date_format.dart';
import '../core/share_ui_copy.dart';
import '../models/workspace.dart';
import '../providers/auth_provider.dart';
import '../providers/share_provider.dart';
import 'package:duoyi/desktop_web/desktop_embedded_scope.dart';

import '../core/design_tokens.dart' show AppSurfaceStyle, DesignTokens;
import '../services/account_local_data_cleaner.dart';
import '../widgets/controller_dialog.dart';
import '../widgets/empty_state.dart';
import '../widgets/surface_components.dart';
import '../widgets/brand_background.dart'
    show BrandBackground, BrandRouteSurface, LocaleStatePreservingRoute;
import 'login_screen.dart';

class ShareScreen extends StatefulWidget implements LocaleStatePreservingRoute {
  const ShareScreen({super.key});

  @override
  State<ShareScreen> createState() => _ShareScreenState();
}

class _ShareScreenState extends State<ShareScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ShareProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, locale, _) {
        final auth = context.watch<AuthProvider>();
        final provider = context.watch<ShareProvider>();
        final cs = Theme.of(context).colorScheme;
        final routeBackground = Theme.of(context).brightness == Brightness.dark
            ? cs.surface
            : cs.surfaceContainerLowest;
        final surfaceStyle = appSurfaceStyleOf(context);
        final isLiquidGlass = surfaceStyle == AppSurfaceStyle.liquidGlass;

        Widget wrapWithBackgroundIfNeeded(Widget scaffold) {
          if (!isLiquidGlass) {
            return scaffold;
          }
          final hasBrandSurface =
              DesktopEmbeddedHostScope.isHosted(context) ||
              context.findAncestorWidgetOfExactType<BrandBackground>() !=
                  null ||
              context.findAncestorWidgetOfExactType<BrandRouteSurface>() !=
                  null;
          if (hasBrandSurface) {
            return scaffold;
          }
          return Material(
            color: routeBackground,
            child: BrandBackground(child: scaffold),
          );
        }

        final theme = Theme.of(context);
        final defaultTextStyle = DefaultTextStyle.of(context).style;
        final appBarTheme = theme.appBarTheme;
        final routeTitleStyle = appSecondaryRouteTitleTextStyle(context);
        final resolvedTitleStyle = defaultTextStyle.merge(
          appBarTheme.titleTextStyle != null
              ? appBarTheme.titleTextStyle!.merge(routeTitleStyle)
              : routeTitleStyle,
        );
        final textLocale = locale == AppLocale.en
            ? const Locale('en')
            : const Locale('zh');
        final textHeightBehavior = DefaultTextHeightBehavior.maybeOf(context);
        final textScaler = MediaQuery.textScalerOf(context);
        final mediaWidth = MediaQuery.sizeOf(context).width;
        final titleText = ShareUiCopy.screenTitle(locale);

        final hasLeading =
            ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
        final leadingWidth = hasLeading
            ? (appBarTheme.leadingWidth ?? kToolbarHeight)
            : 0.0;
        final baseTitleSpacing =
            appBarTheme.titleSpacing ?? NavigationToolbar.kMiddleSpacing;
        final effectiveTitleSpacing = (mediaWidth < 360 && hasLeading)
            ? 8.0
            : baseTitleSpacing;

        final baseToolbarHeight = appBarTheme.toolbarHeight ?? kToolbarHeight;

        if (!auth.state.isLoggedIn) {
          final maxTitleWidth = math.max(
            0.0,
            mediaWidth - leadingWidth - effectiveTitleSpacing,
          );
          final titlePainter = TextPainter(
            text: TextSpan(
              text: titleText,
              style: resolvedTitleStyle,
              locale: textLocale,
            ),
            textDirection: Directionality.of(context),
            textScaler: textScaler,
            textHeightBehavior: textHeightBehavior,
          )..layout(maxWidth: maxTitleWidth);
          final titleLineCount = titlePainter.computeLineMetrics().length;
          final titleHeight = titlePainter.height;
          titlePainter.dispose();

          final effectiveToolbarHeight = titleLineCount > 1
              ? math.max(baseToolbarHeight, titleHeight + 16.0)
              : baseToolbarHeight;

          return wrapWithBackgroundIfNeeded(
            Scaffold(
              backgroundColor: isLiquidGlass
                  ? Colors.transparent
                  : routeBackground,
              appBar: AppBar(
                title: Text(
                  titleText,
                  softWrap: true,
                  overflow: TextOverflow.visible,
                ),
                titleTextStyle: resolvedTitleStyle,
                toolbarHeight: effectiveToolbarHeight,
                titleSpacing: effectiveTitleSpacing,
                centerTitle: titleLineCount > 1 ? false : null,
                backgroundColor: routeBackground.withValues(alpha: 0.96),
                surfaceTintColor: Colors.transparent,
              ),
              body: AppSecondaryControlTheme(
                child: EmptyState(
                  icon: Icons.group_outlined,
                  message: ShareUiCopy.loggedOutMessage(locale),
                  actionLabel: ShareUiCopy.actionLogin(locale),
                  onAction: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  ),
                ),
              ),
            ),
          );
        }

        const actionsWidth = 48.0 * 3; // 144.0
        final maxTitleWidth = math.max(
          0.0,
          mediaWidth - leadingWidth - actionsWidth - effectiveTitleSpacing,
        );
        final titlePainter = TextPainter(
          text: TextSpan(
            text: titleText,
            style: resolvedTitleStyle,
            locale: textLocale,
          ),
          textDirection: Directionality.of(context),
          textScaler: textScaler,
          textHeightBehavior: textHeightBehavior,
        )..layout(maxWidth: maxTitleWidth);
        final titleLineCount = titlePainter.computeLineMetrics().length;
        final titleHeight = titlePainter.height;
        titlePainter.dispose();

        final effectiveToolbarHeight = titleLineCount > 1
            ? math.max(baseToolbarHeight, titleHeight + 16.0)
            : baseToolbarHeight;

        return wrapWithBackgroundIfNeeded(
          Scaffold(
            backgroundColor: isLiquidGlass
                ? Colors.transparent
                : routeBackground,
            appBar: AppBar(
              title: Text(
                titleText,
                softWrap: true,
                overflow: TextOverflow.visible,
              ),
              titleTextStyle: resolvedTitleStyle,
              toolbarHeight: effectiveToolbarHeight,
              titleSpacing: effectiveTitleSpacing,
              centerTitle: titleLineCount > 1 ? false : null,
              backgroundColor: routeBackground.withValues(alpha: 0.96),
              surfaceTintColor: Colors.transparent,
              actions: [
                _MentionInboxButton(
                  unreadCount: provider.unreadMentionCount,
                  locale: locale,
                  onPressed: () => _openMentionInbox(context),
                ),
                IconButton(
                  tooltip: ShareUiCopy.actionJoinTooltip(locale),
                  onPressed: () => _acceptInvite(context),
                  icon: const Icon(Icons.qr_code_2),
                ),
                IconButton(
                  tooltip: ShareUiCopy.actionRefreshTooltip(locale),
                  onPressed: provider.loading
                      ? null
                      : () => provider.load(force: true),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            body: AppSecondaryControlTheme(
              child: RefreshIndicator(
                onRefresh: () => provider.load(force: true),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                  children: [
                    AppSurfaceCard(
                      padding: const EdgeInsets.all(16),
                      gradient: LinearGradient(
                        colors: [
                          cs.primary.withValues(alpha: 0.12),
                          cs.surface,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final isCompact = constraints.maxWidth < 360;
                          final content = Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                ShareUiCopy.screenTitle(locale),
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.normal),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                ShareUiCopy.heroDescription(locale),
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: appSecondaryDescriptionColor(
                                        context,
                                        isHero: true,
                                      ),
                                    ),
                              ),
                            ],
                          );
                          final createBtn = FilledButton.tonalIcon(
                            onPressed: () => _createWorkspace(context),
                            icon: const Icon(Icons.add),
                            label: Text(ShareUiCopy.actionNew(locale)),
                          );
                          if (isCompact) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: cs.primary.withValues(
                                          alpha: 0.14,
                                        ),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Icon(
                                        Icons.group_outlined,
                                        color: cs.primary,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(child: content),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: createBtn,
                                ),
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: cs.primary.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Icon(
                                  Icons.group_outlined,
                                  color: cs.primary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: content),
                              const SizedBox(width: 8),
                              createBtn,
                            ],
                          );
                        },
                      ),
                    ),
                    if (provider.lastError != null) ...[
                      const SizedBox(height: 12),
                      AppSurfaceCard(
                        padding: const EdgeInsets.all(12),
                        border: Border.all(
                          color: cs.error.withValues(alpha: 0.32),
                          width: 0.45,
                        ),
                        child: Text(
                          provider.lastError!,
                          style: TextStyle(color: cs.error),
                        ),
                      ),
                    ],
                    AppSectionHeader(
                      title: ShareUiCopy.myWorkspacesTitle(locale),
                      subtitle: ShareUiCopy.myWorkspacesSubtitle(locale),
                      wrapText: true,
                    ),
                    if (provider.loading)
                      const Padding(
                        padding: EdgeInsets.all(28),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (provider.workspaces.isEmpty)
                      EmptyState(
                        icon: Icons.group_add_outlined,
                        message: ShareUiCopy.emptyWorkspacesMessage(locale),
                        actionLabel: ShareUiCopy.emptyWorkspacesAction(locale),
                        onAction: () => _createWorkspace(context),
                      )
                    else
                      ...provider.workspaces.map(
                        (workspace) => _WorkspaceCard(
                          workspace: workspace,
                          locale: locale,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openMentionInbox(BuildContext context) async {
    final rootRoute = ModalRoute.of(context);
    if (rootRoute == null || !rootRoute.isCurrent) return;

    final origin = _ShareActionOrigin.capture(context);
    if (origin == null ||
        origin.leaseCaptureFailed ||
        !origin.isValid(context)) {
      if (context.mounted) {
        _showSafeFeedback(
          context,
          (locale) => ShareUiCopy.serviceUnavailable(locale),
        );
      }
      return;
    }

    await origin.share.loadMentionInbox();
    if (!context.mounted || !rootRoute.isCurrent || !origin.isValid(context)) {
      return;
    }

    await showAppModalSheet(
      context: context,
      builder: (sheetContext) => _MentionInboxSheet(
        origin: origin,
        onOpenMention: (mention) =>
            _openMentionContext(context, sheetContext, mention, origin),
      ),
    );
  }

  Future<void> _openMentionContext(
    BuildContext context,
    BuildContext sheetContext,
    WorkspaceMention mention,
    _ShareActionOrigin inboxOrigin,
  ) async {
    final sheetRoute = ModalRoute.of(sheetContext);
    if (!sheetContext.mounted || sheetRoute == null || !sheetRoute.isCurrent) {
      return;
    }
    if (!inboxOrigin.isValid(sheetContext)) return;

    try {
      if (mention.isUnread) {
        await inboxOrigin.share.markMentionRead(mention.id);
        if (!sheetContext.mounted || !sheetRoute.isCurrent) {
          return;
        }
        if (!inboxOrigin.isValid(sheetContext)) return;
      }

      await inboxOrigin.share.loadWorkspaceCollaboration(mention.workspaceId);
      if (!sheetContext.mounted || !sheetRoute.isCurrent) {
        return;
      }
      if (!inboxOrigin.isValid(sheetContext)) return;

      Navigator.pop(sheetContext);

      final rootRoute = ModalRoute.of(context);
      if (!context.mounted ||
          rootRoute == null ||
          !rootRoute.isCurrent ||
          !inboxOrigin.isValid(context)) {
        return;
      }

      final workspace = inboxOrigin.share.workspaceById(mention.workspaceId);
      await showAppModalSheet(
        context: context,
        builder: (_) => _WorkspaceCollaborationSheet(
          workspace: workspace ?? mention.asWorkspaceFallback,
          focusTargetId: mention.targetId,
          focusCommentId: mention.commentId,
          origin: inboxOrigin,
        ),
      );
    } catch (e) {
      if (!sheetContext.mounted ||
          !sheetRoute.isCurrent ||
          !inboxOrigin.isValid(sheetContext)) {
        return;
      }
      _showSafeFeedback(
        sheetContext,
        (locale) => locale == AppLocale.en
            ? ShareUiCopy.openMentionFailed(_shareError(e, locale), locale)
            : '打开提及失败: ${_shareError(e)}',
      );
    }
  }

  static ButtonStyle _dialogCancelButtonStyle(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surfaceStyle = appSurfaceStyleOf(context);
    final isPriorityTheme =
        !isDark &&
        (surfaceStyle == AppSurfaceStyle.ios ||
            surfaceStyle == AppSurfaceStyle.liquidGlass);
    if (!isPriorityTheme) {
      return const ButtonStyle();
    }
    final cs = theme.colorScheme;
    final dialogBg =
        theme.dialogTheme.backgroundColor ?? cs.surfaceContainerHigh;
    final compositedBg = Color.alphaBlend(dialogBg, Colors.white);
    return TextButton.styleFrom(
      foregroundColor: appReadableForeground(compositedBg, cs.primary),
      minimumSize: const Size(44, 44),
    );
  }

  Future<void> _createWorkspace(BuildContext context) async {
    final rootRoute = ModalRoute.of(context);
    if (rootRoute == null || !rootRoute.isCurrent) return;

    final origin = _ShareActionOrigin.capture(context);
    if (origin == null ||
        origin.leaseCaptureFailed ||
        !origin.isValid(context)) {
      if (context.mounted) {
        _showSafeFeedback(
          context,
          (locale) => ShareUiCopy.serviceUnavailable(locale),
        );
      }
      return;
    }

    final ctrl = TextEditingController();
    var isSubmitting = false;
    String? completedResult;

    await showControllerDialog<String>(
      context: context,
      controllers: [ctrl],
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) =>
            ValueListenableBuilder<AppLocale>(
              valueListenable: I18n.localeListenable,
              builder: (dialogCtx, locale, _) {
                Future<void> submit() async {
                  final dialogRoute = ModalRoute.of(dialogCtx);
                  if (!dialogCtx.mounted ||
                      dialogRoute == null ||
                      !dialogRoute.isCurrent) {
                    return;
                  }
                  if (completedResult != null) {
                    if (origin.isValid(dialogCtx)) {
                      Navigator.pop(dialogCtx, completedResult);
                    }
                    return;
                  }
                  final name = ctrl.text.trim();
                  if (name.isEmpty) return;
                  if (isSubmitting) return;
                  if (!origin.isValid(dialogCtx)) return;
                  setDialogState(() => isSubmitting = true);
                  try {
                    await origin.share.createWorkspace(name);
                    if (!dialogCtx.mounted || !origin.isValid(dialogCtx)) {
                      return;
                    }
                    setDialogState(() {
                      isSubmitting = false;
                      completedResult = name;
                    });
                    if (dialogRoute.isCurrent) {
                      Navigator.pop(dialogCtx, name);
                    }
                  } catch (e) {
                    if (!dialogCtx.mounted || !origin.isValid(dialogCtx)) {
                      return;
                    }
                    setDialogState(() => isSubmitting = false);
                    if (dialogRoute.isCurrent) {
                      _showSafeFeedback(
                        dialogCtx,
                        (loc) => ShareUiCopy.createWorkspaceFailed(
                          ShareUiCopy.error(e, loc),
                          loc,
                        ),
                      );
                    }
                  }
                }

                return AppDialog(
                  title: Text(ShareUiCopy.createWorkspaceTitle(locale)),
                  content: SingleChildScrollView(
                    child: TextField(
                      controller: ctrl,
                      autofocus: completedResult == null,
                      readOnly: completedResult != null,
                      decoration: InputDecoration(
                        labelText: ShareUiCopy.workspaceNameLabel(locale),
                      ),
                      onSubmitted: (isSubmitting || completedResult != null)
                          ? null
                          : (_) => submit(),
                    ),
                  ),
                  actions: [
                    TextButton(
                      style: _dialogCancelButtonStyle(dialogCtx),
                      onPressed: isSubmitting
                          ? null
                          : () {
                              final route = ModalRoute.of(dialogCtx);
                              if (dialogCtx.mounted &&
                                  route != null &&
                                  route.isCurrent) {
                                Navigator.pop(dialogCtx);
                              }
                            },
                      child: Text(ShareUiCopy.actionCancel(locale)),
                    ),
                    FilledButton(
                      onPressed: isSubmitting ? null : submit,
                      child: isSubmitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              completedResult != null
                                  ? ShareUiCopy.actionDone(locale)
                                  : ShareUiCopy.actionCreate(locale),
                            ),
                    ),
                  ],
                );
              },
            ),
      ),
    );
  }

  Future<void> _acceptInvite(BuildContext context) async {
    final rootRoute = ModalRoute.of(context);
    if (rootRoute == null || !rootRoute.isCurrent) return;

    final origin = _ShareActionOrigin.capture(context);
    if (origin == null ||
        origin.leaseCaptureFailed ||
        !origin.isValid(context)) {
      if (context.mounted) {
        _showSafeFeedback(
          context,
          (locale) => ShareUiCopy.serviceUnavailable(locale),
        );
      }
      return;
    }

    final ctrl = TextEditingController();
    var isSubmitting = false;
    String? completedResult;

    final acceptedCode = await showControllerDialog<String>(
      context: context,
      controllers: [ctrl],
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) =>
            ValueListenableBuilder<AppLocale>(
              valueListenable: I18n.localeListenable,
              builder: (dialogCtx, locale, _) {
                Future<void> submit() async {
                  final dialogRoute = ModalRoute.of(dialogCtx);
                  if (!dialogCtx.mounted ||
                      dialogRoute == null ||
                      !dialogRoute.isCurrent) {
                    return;
                  }
                  if (completedResult != null) {
                    if (origin.isValid(dialogCtx)) {
                      Navigator.pop(dialogCtx, completedResult);
                    }
                    return;
                  }
                  final code = ctrl.text.trim();
                  if (code.isEmpty) return;
                  if (isSubmitting) return;
                  if (!origin.isValid(dialogCtx)) return;
                  setDialogState(() => isSubmitting = true);
                  try {
                    await origin.share.acceptInvite(code);
                    if (!dialogCtx.mounted || !origin.isValid(dialogCtx)) {
                      return;
                    }
                    setDialogState(() {
                      isSubmitting = false;
                      completedResult = code;
                    });
                    if (dialogRoute.isCurrent) {
                      Navigator.pop(dialogCtx, code);
                    }
                  } catch (e) {
                    if (!dialogCtx.mounted || !origin.isValid(dialogCtx)) {
                      return;
                    }
                    setDialogState(() => isSubmitting = false);
                    if (dialogRoute.isCurrent) {
                      _showSafeFeedback(
                        dialogCtx,
                        (loc) => ShareUiCopy.joinWorkspaceFailed(
                          ShareUiCopy.error(e, loc),
                          loc,
                        ),
                      );
                    }
                  }
                }

                return AppDialog(
                  title: Text(ShareUiCopy.joinWorkspaceTitle(locale)),
                  content: SingleChildScrollView(
                    child: TextField(
                      controller: ctrl,
                      autofocus: completedResult == null,
                      readOnly: completedResult != null,
                      decoration: InputDecoration(
                        labelText: ShareUiCopy.inviteCodeLabel(locale),
                      ),
                      onSubmitted: (isSubmitting || completedResult != null)
                          ? null
                          : (_) => submit(),
                    ),
                  ),
                  actions: [
                    TextButton(
                      style: _dialogCancelButtonStyle(dialogCtx),
                      onPressed: isSubmitting
                          ? null
                          : () {
                              final route = ModalRoute.of(dialogCtx);
                              if (dialogCtx.mounted &&
                                  route != null &&
                                  route.isCurrent) {
                                Navigator.pop(dialogCtx);
                              }
                            },
                      child: Text(ShareUiCopy.actionCancel(locale)),
                    ),
                    FilledButton(
                      onPressed: isSubmitting ? null : submit,
                      child: isSubmitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              completedResult != null
                                  ? ShareUiCopy.actionDone(locale)
                                  : ShareUiCopy.actionJoin(locale),
                            ),
                    ),
                  ],
                );
              },
            ),
      ),
    );
    if (acceptedCode == null ||
        !context.mounted ||
        !rootRoute.isCurrent ||
        !origin.isValid(context)) {
      return;
    }
    _showSafeFeedback(
      context,
      (locale) => ShareUiCopy.joinedWorkspaceSuccess(locale),
    );
  }
}

class _MentionInboxButton extends StatelessWidget {
  final int unreadCount;
  final VoidCallback onPressed;
  final AppLocale? locale;

  const _MentionInboxButton({
    required this.unreadCount,
    required this.onPressed,
    this.locale,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveLocale = locale ?? I18n.current;
    final isEn = effectiveLocale == AppLocale.en;
    final cs = Theme.of(context).colorScheme;
    final tooltip = isEn
        ? ShareUiCopy.mentionInboxTooltip(unreadCount, effectiveLocale)
        : (unreadCount > 0 ? '$unreadCount 条未读提及' : '@ 提及');
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.alternate_email_outlined),
          if (unreadCount > 0)
            Positioned(
              right: -7,
              top: -7,
              child: Container(
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: cs.error,
                  borderRadius: BorderRadius.circular(999),
                ),
                alignment: Alignment.center,
                child: Text(
                  unreadCount > 99 ? '99+' : '$unreadCount',
                  style: TextStyle(
                    color: cs.onError,
                    fontSize: 9,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MentionInboxSheet extends StatelessWidget {
  final ValueChanged<WorkspaceMention> onOpenMention;
  final _ShareActionOrigin? origin;

  const _MentionInboxSheet({required this.onOpenMention, this.origin});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ShareProvider>();
    final mentions = provider.mentions;
    final cs = Theme.of(context).colorScheme;
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, locale, _) {
        final isEn = locale == AppLocale.en;
        final sheetTitle = isEn
            ? ShareUiCopy.mentionInboxTitle(locale)
            : '@ 提及';
        return AppModalSheet(
          title: sheetTitle,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (mentions.isEmpty)
                  _EmptyCollaborationLine(
                    icon: Icons.alternate_email_outlined,
                    text: ShareUiCopy.mentionInboxEmpty(locale),
                    color: cs.onSurfaceVariant,
                  )
                else
                  ...mentions
                      .take(20)
                      .map(
                        (mention) => _MentionTile(
                          mention: mention,
                          locale: locale,
                          onOpen: () => onOpenMention(mention),
                        ),
                      ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MentionTile extends StatelessWidget {
  final WorkspaceMention mention;
  final VoidCallback onOpen;
  final AppLocale? locale;

  const _MentionTile({
    required this.mention,
    required this.onOpen,
    this.locale,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveLocale = locale ?? I18n.current;
    final cs = Theme.of(context).colorScheme;
    final author = mention.authorName.isEmpty
        ? mention.authorUserId
        : mention.authorName;
    final avatar = CircleAvatar(
      radius: 15,
      backgroundColor: mention.isUnread
          ? cs.primary.withValues(alpha: 0.16)
          : cs.surfaceContainerHighest,
      child: Icon(
        mention.isUnread
            ? Icons.alternate_email
            : Icons.alternate_email_outlined,
        size: 16,
        color: mention.isUnread ? cs.primary : cs.onSurfaceVariant,
      ),
    );

    final action = mention.isUnread
        ? FilledButton.tonal(
            style: FilledButton.styleFrom(
              minimumSize: const Size(44, 44),
              visualDensity: VisualDensity.standard,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: onOpen,
            child: Text(ShareUiCopy.actionView(effectiveLocale)),
          )
        : const Icon(Icons.chevron_right);

    final bodyText = Text(
      mention.body,
      style: TextStyle(
        color: mention.isUnread ? cs.onSurface : cs.onSurfaceVariant,
      ),
    );

    final subtitleText = Text(
      '$author · ${mention.workspaceName} · ${_formatShortTime(mention.createdAt)}',
      style: const TextStyle(fontSize: 11),
    );

    final mediaWidth = MediaQuery.sizeOf(context).width;
    final textScaler = MediaQuery.textScalerOf(context);
    final isStacked = mediaWidth < 480 || textScaler.scale(14) >= 20;

    if (isStacked) {
      return ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        onTap: onOpen,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [avatar, action],
            ),
            const SizedBox(height: 6),
            bodyText,
          ],
        ),
        subtitle: subtitleText,
      );
    }

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      onTap: onOpen,
      leading: avatar,
      title: bodyText,
      subtitle: subtitleText,
      trailing: action,
    );
  }
}

class _WorkspaceCard extends StatelessWidget {
  final Workspace workspace;
  final AppLocale? locale;

  const _WorkspaceCard({required this.workspace, this.locale});

  @override
  Widget build(BuildContext context) {
    final effectiveLocale = locale ?? I18n.current;
    final isEn = effectiveLocale == AppLocale.en;
    final auth = context.watch<AuthProvider>();
    final role = workspace.roleFor(auth.state.userId);
    final cs = Theme.of(context).colorScheme;
    final color = workspace.isPrivate ? cs.onSurfaceVariant : cs.primary;
    final roleLabel = role.labelFor(effectiveLocale);
    final membersSubtitle = ShareUiCopy.membersCount(
      workspace.members.length,
      roleLabel,
      effectiveLocale,
    );
    final collabTooltip = isEn
        ? ShareUiCopy.collaborationTooltip(effectiveLocale)
        : '协作动态';
    final actionButtons = <Widget>[
      IconButton(
        tooltip: collabTooltip,
        visualDensity: VisualDensity.standard,
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        onPressed: () => _openCollaboration(context, workspace),
        icon: const Icon(Icons.forum_outlined),
      ),
      if (role.canEdit)
        IconButton(
          tooltip: ShareUiCopy.createInviteTooltip(effectiveLocale),
          visualDensity: VisualDensity.standard,
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          onPressed: () => _createInvite(context, workspace),
          icon: const Icon(Icons.person_add_alt_1_outlined),
        ),
    ];
    return AppSurfaceCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      border: Border.all(color: color.withValues(alpha: 0.18), width: 0.45),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cardWidth = constraints.maxWidth;
          const leadingWidth = 42.0 + 12.0;
          final hasActions = !workspace.isPrivate && actionButtons.isNotEmpty;
          final actionCount = actionButtons.length;
          // 标准密度且开启 materialTapTargetSize: padded 时，每个交互按钮实际占用 48px
          const buttonWidth = 48.0;
          final actionsInlineWidth = hasActions
              ? (4.0 + actionCount * buttonWidth)
              : 0.0;
          final availableInlineWidth =
              cardWidth - leadingWidth - actionsInlineWidth;

          final defaultTextStyle = DefaultTextStyle.of(context);
          final titleBaseStyle = Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.normal);
          final effectiveTitleStyle = defaultTextStyle.style.merge(
            titleBaseStyle,
          );
          final subtitleBaseStyle = TextStyle(
            fontSize: 12,
            color: appSecondaryDescriptionColor(context),
          );
          final effectiveSubtitleStyle = defaultTextStyle.style.merge(
            subtitleBaseStyle,
          );
          final textScaler = MediaQuery.textScalerOf(context);
          final textDirection = Directionality.of(context);

          double maxTitleWordWidth = 0.0;
          final trimmedName = workspace.name.trim();
          if (trimmedName.isNotEmpty) {
            for (final word in trimmedName.split(RegExp(r'\s+'))) {
              if (word.isEmpty) continue;
              final painter = TextPainter(
                text: TextSpan(text: word, style: effectiveTitleStyle),
                textDirection: textDirection,
                textScaler: textScaler,
              )..layout();
              final width = painter.width;
              painter.dispose();
              if (width > maxTitleWordWidth) {
                maxTitleWordWidth = width;
              }
            }
          }

          double maxSubtitleWordWidth = 0.0;
          final trimmedSubtitle = membersSubtitle.trim();
          if (trimmedSubtitle.isNotEmpty) {
            for (final word in trimmedSubtitle.split(RegExp(r'\s+'))) {
              if (word.isEmpty) continue;
              final painter = TextPainter(
                text: TextSpan(text: word, style: effectiveSubtitleStyle),
                textDirection: textDirection,
                textScaler: textScaler,
              )..layout();
              final width = painter.width;
              painter.dispose();
              if (width > maxSubtitleWordWidth) {
                maxSubtitleWordWidth = width;
              }
            }
          }

          final bool actionsInline =
              !hasActions ||
              cardWidth.isInfinite ||
              (maxTitleWordWidth <= availableInlineWidth &&
                  maxSubtitleWordWidth <= availableInlineWidth);

          final headerContent = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                workspace.name,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.normal,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                membersSubtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: appSecondaryDescriptionColor(context),
                ),
              ),
              if (workspace.members.isNotEmpty) ...[
                const SizedBox(height: 8),
                _MemberAvatarStack(
                  members: workspace.members,
                  locale: effectiveLocale,
                ),
              ],
            ],
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      workspace.isPrivate
                          ? Icons.lock_outline
                          : Icons.groups_2_outlined,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: headerContent),
                  if (actionsInline && hasActions) ...[
                    const SizedBox(width: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: actionButtons,
                    ),
                  ],
                ],
              ),
              if (!actionsInline && hasActions) ...[
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: actionButtons,
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: workspace.members
                    .map(
                      (member) => _MemberChip(
                        member: member,
                        workspace: workspace,
                        locale: effectiveLocale,
                      ),
                    )
                    .toList(),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _createInvite(BuildContext context, Workspace workspace) async {
    final rootRoute = ModalRoute.of(context);
    if (rootRoute == null || !rootRoute.isCurrent) return;

    final origin = _ShareActionOrigin.capture(context);
    if (origin == null ||
        origin.leaseCaptureFailed ||
        !origin.isValid(context)) {
      if (context.mounted) {
        _showSafeFeedback(
          context,
          (locale) => ShareUiCopy.serviceUnavailable(locale),
        );
      }
      return;
    }

    var role = WorkspaceRole.viewer;
    var isSubmitting = false;
    ShareInvite? completedResult;

    final invite = await showControllerDialog<ShareInvite>(
      context: context,
      controllers: const <TextEditingController>[],
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) =>
            ValueListenableBuilder<AppLocale>(
              valueListenable: I18n.localeListenable,
              builder: (dialogCtx, locale, _) {
                Future<void> submit() async {
                  final dialogRoute = ModalRoute.of(dialogCtx);
                  if (!dialogCtx.mounted ||
                      dialogRoute == null ||
                      !dialogRoute.isCurrent) {
                    return;
                  }
                  if (completedResult != null) {
                    if (origin.isValid(dialogCtx)) {
                      Navigator.pop(dialogCtx, completedResult);
                    }
                    return;
                  }
                  if (isSubmitting) return;
                  if (!origin.isValid(dialogCtx)) return;
                  setDialogState(() => isSubmitting = true);
                  try {
                    final created = await origin.share.createInvite(
                      workspace.id,
                      role: role,
                    );
                    if (!dialogCtx.mounted || !origin.isValid(dialogCtx)) {
                      return;
                    }
                    setDialogState(() {
                      isSubmitting = false;
                      completedResult = created;
                    });
                    if (dialogRoute.isCurrent) {
                      Navigator.pop(dialogCtx, created);
                    }
                  } catch (e) {
                    if (!dialogCtx.mounted || !origin.isValid(dialogCtx)) {
                      return;
                    }
                    setDialogState(() => isSubmitting = false);
                    if (dialogRoute.isCurrent) {
                      _showSafeFeedback(
                        dialogCtx,
                        (loc) => ShareUiCopy.createInviteFailed(
                          ShareUiCopy.error(e, loc),
                          loc,
                        ),
                      );
                    }
                  }
                }

                return AppDialog(
                  title: Text(ShareUiCopy.createInviteTitle(locale)),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(ShareUiCopy.roleReadOnlyTitle(locale)),
                          trailing: role == WorkspaceRole.viewer
                              ? Icon(
                                  Icons.check,
                                  color: Theme.of(
                                    dialogCtx,
                                  ).colorScheme.primary,
                                )
                              : null,
                          onTap: (isSubmitting || completedResult != null)
                              ? null
                              : () => setDialogState(
                                  () => role = WorkspaceRole.viewer,
                                ),
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(ShareUiCopy.roleCanEditTitle(locale)),
                          trailing: role == WorkspaceRole.editor
                              ? Icon(
                                  Icons.check,
                                  color: Theme.of(
                                    dialogCtx,
                                  ).colorScheme.primary,
                                )
                              : null,
                          onTap: (isSubmitting || completedResult != null)
                              ? null
                              : () => setDialogState(
                                  () => role = WorkspaceRole.editor,
                                ),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      style: _ShareScreenState._dialogCancelButtonStyle(
                        dialogCtx,
                      ),
                      onPressed: isSubmitting
                          ? null
                          : () {
                              final route = ModalRoute.of(dialogCtx);
                              if (dialogCtx.mounted &&
                                  route != null &&
                                  route.isCurrent) {
                                Navigator.pop(dialogCtx);
                              }
                            },
                      child: Text(ShareUiCopy.actionCancel(locale)),
                    ),
                    FilledButton(
                      onPressed: isSubmitting ? null : submit,
                      child: isSubmitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              completedResult != null
                                  ? ShareUiCopy.actionDone(locale)
                                  : ShareUiCopy.actionGenerate(locale),
                            ),
                    ),
                  ],
                );
              },
            ),
      ),
    );

    if (invite == null ||
        !context.mounted ||
        !rootRoute.isCurrent ||
        !origin.isValid(context)) {
      return;
    }

    await Clipboard.setData(ClipboardData(text: invite.code));
    if (!context.mounted || !rootRoute.isCurrent || !origin.isValid(context)) {
      return;
    }

    final resultRoute = createControllerDialogRoute<void>(
      context: context,
      builder: (resultDialogCtx) => ValueListenableBuilder<AppLocale>(
        valueListenable: I18n.localeListenable,
        builder: (resultDialogCtx, locale, _) => AppDialog(
          title: Text(ShareUiCopy.inviteCopiedTitle(locale)),
          content: SingleChildScrollView(
            child: SelectableText(
              '${invite.code}\n\n${ShareUiCopy.roleLabelPrefix(invite.role.labelFor(locale), locale)}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.normal,
              ),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () {
                final route = ModalRoute.of(resultDialogCtx);
                if (resultDialogCtx.mounted &&
                    route != null &&
                    route.isCurrent) {
                  Navigator.pop(resultDialogCtx);
                }
              },
              child: Text(ShareUiCopy.actionDone(locale)),
            ),
          ],
        ),
      ),
    );
    await Navigator.of(context, rootNavigator: true).push<void>(resultRoute);
  }

  Future<void> _openCollaboration(
    BuildContext context,
    Workspace workspace,
  ) async {
    final rootRoute = ModalRoute.of(context);
    if (rootRoute == null || !rootRoute.isCurrent) return;

    final origin = _ShareActionOrigin.capture(context);
    if (origin == null ||
        origin.leaseCaptureFailed ||
        !origin.isValid(context)) {
      if (context.mounted) {
        _showSafeFeedback(
          context,
          (locale) => ShareUiCopy.serviceUnavailable(locale),
        );
      }
      return;
    }

    try {
      await origin.share.loadWorkspaceCollaboration(workspace.id);
      if (!context.mounted ||
          !rootRoute.isCurrent ||
          !origin.isValid(context)) {
        return;
      }
      await showAppModalSheet(
        context: context,
        builder: (_) =>
            _WorkspaceCollaborationSheet(workspace: workspace, origin: origin),
      );
    } catch (e) {
      if (!context.mounted ||
          !rootRoute.isCurrent ||
          !origin.isValid(context)) {
        return;
      }
      _showSafeFeedback(context, (locale) => _shareError(e, locale));
    }
  }
}

class _WorkspaceCollaborationSheet extends StatefulWidget {
  final Workspace workspace;
  final String? focusTargetId;
  final String? focusCommentId;
  final _ShareActionOrigin? origin;

  const _WorkspaceCollaborationSheet({
    required this.workspace,
    this.focusTargetId,
    this.focusCommentId,
    this.origin,
  });

  @override
  State<_WorkspaceCollaborationSheet> createState() =>
      _WorkspaceCollaborationSheetState();
}

class _WorkspaceCollaborationSheetState
    extends State<_WorkspaceCollaborationSheet> {
  final _commentCtrl = TextEditingController();
  var _submitting = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ShareProvider>();
    final comments = provider.commentsFor(widget.workspace.id);
    final focusTargetId = widget.focusTargetId;
    final hasFocusTarget = focusTargetId != null && focusTargetId.isNotEmpty;
    final focusComments = !hasFocusTarget
        ? const <WorkspaceComment>[]
        : provider.commentsForTarget(widget.workspace.id, focusTargetId);
    final activities = provider.activitiesFor(widget.workspace.id);
    final leaderboard = provider.leaderboardFor(widget.workspace.id);
    final cs = Theme.of(context).colorScheme;

    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, locale, _) {
        final isEn = locale == AppLocale.en;
        final commentHint = isEn
            ? ShareUiCopy.commentInputHint(locale)
            : '写评论，@用户名/邮箱/昵称 可提醒成员';
        final leaderboardTitle = isEn
            ? ShareUiCopy.memberLeaderboardTitle(locale)
            : '成员排行榜';
        final activitiesTitle = isEn
            ? ShareUiCopy.activitiesTitle(locale)
            : '动态流';

        return AppModalSheet(
          title: ShareUiCopy.collaborationSheetTitle(
            widget.workspace.name,
            locale,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _commentCtrl,
                  minLines: 1,
                  maxLines: 3,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.mode_comment_outlined),
                    hintText: commentHint,
                    suffixIcon: IconButton(
                      tooltip: ShareUiCopy.actionSend(locale),
                      icon: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_outlined),
                      onPressed: _submitting ? null : () => _send(context),
                    ),
                  ),
                  onSubmitted: _submitting ? null : (_) => _send(context),
                ),
                const SizedBox(height: 12),
                if (hasFocusTarget) ...[
                  _MentionContextBlock(
                    targetId: focusTargetId,
                    commentId: widget.focusCommentId ?? '',
                    comments: focusComments,
                    locale: locale,
                  ),
                  const SizedBox(height: 12),
                ],
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    leaderboardTitle,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                const SizedBox(height: 8),
                if (leaderboard.isEmpty)
                  _EmptyCollaborationLine(
                    icon: Icons.leaderboard_outlined,
                    text: ShareUiCopy.memberLeaderboardEmpty(locale),
                    color: cs.onSurfaceVariant,
                  )
                else
                  ...leaderboard
                      .take(5)
                      .mapIndexed(
                        (index, entry) => _LeaderboardTile(
                          rank: index + 1,
                          entry: entry,
                          locale: locale,
                        ),
                      ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    ShareUiCopy.latestCommentsTitle(locale),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                const SizedBox(height: 8),
                if (comments.isEmpty)
                  _EmptyCollaborationLine(
                    icon: Icons.forum_outlined,
                    text: ShareUiCopy.latestCommentsEmpty(locale),
                    color: cs.onSurfaceVariant,
                  )
                else
                  ...comments
                      .take(5)
                      .map((comment) => _CommentTile(comment, locale: locale)),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    activitiesTitle,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                const SizedBox(height: 8),
                if (activities.isEmpty)
                  _EmptyCollaborationLine(
                    icon: Icons.history,
                    text: ShareUiCopy.activitiesEmpty(locale),
                    color: cs.onSurfaceVariant,
                  )
                else
                  ...activities
                      .take(8)
                      .map(
                        (activity) => _ActivityTile(activity, locale: locale),
                      ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _send(BuildContext context) async {
    if (_submitting) return;
    final sheetRoute = ModalRoute.of(context);
    if (!context.mounted || sheetRoute == null || !sheetRoute.isCurrent) {
      return;
    }
    final submittedValue = _commentCtrl.value;
    final body = submittedValue.text.trim();
    if (body.isEmpty) return;

    final origin = widget.origin ?? _ShareActionOrigin.capture(context);
    if (origin == null || !origin.isValid(context)) return;

    setState(() => _submitting = true);
    try {
      await context.read<ShareProvider>().createComment(
        widget.workspace.id,
        body,
      );
      if (!context.mounted ||
          !sheetRoute.isCurrent ||
          !origin.isValid(context)) {
        return;
      }
      if (_commentCtrl.value == submittedValue) {
        if (!context.mounted) return;
        _commentCtrl.clear();
      }
    } catch (e) {
      if (!context.mounted ||
          !sheetRoute.isCurrent ||
          !origin.isValid(context)) {
        return;
      }
      _showSafeFeedback(
        context,
        (locale) =>
            ShareUiCopy.sendCommentFailed(_shareError(e, locale), locale),
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }
}

void _showSafeFeedback(
  BuildContext context,
  String Function(AppLocale locale) messageBuilder,
) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: ValueListenableBuilder<AppLocale>(
        valueListenable: I18n.localeListenable,
        builder: (context, locale, _) => Text(messageBuilder(locale)),
      ),
    ),
  );
}

String _shareError(Object error, [AppLocale? locale]) {
  // Localized via ShareUiCopy.error, wrapping userVisibleApiError(error) safely.
  return ShareUiCopy.error(error, locale);
}

class _ShareActionOrigin {
  final AuthProvider auth;
  final ShareProvider share;
  final AuthSessionLease? sessionLease;
  final bool leaseCaptureFailed;
  String? _userId;
  final int accountGeneration;
  final ModalRoute<dynamic>? ownerRoute;

  _ShareActionOrigin._({
    required this.auth,
    required this.share,
    required this.sessionLease,
    required this.leaseCaptureFailed,
    required String? userId,
    required this.accountGeneration,
    required this.ownerRoute,
  }) : _userId = _normalizeUserId(userId);

  static String? _normalizeUserId(String? id) {
    if (id == null) return null;
    final trimmed = id.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static _ShareActionOrigin? capture(BuildContext context) {
    try {
      final auth = context.read<AuthProvider>();
      final share = context.read<ShareProvider>();
      AuthSessionLease? lease;
      var failed = false;
      if (auth.state.isLoggedIn) {
        try {
          lease = auth.captureSessionLease();
        } catch (_) {
          lease = null;
          failed = true;
        }
      }
      return _ShareActionOrigin._(
        auth: auth,
        share: share,
        sessionLease: lease,
        leaseCaptureFailed: failed,
        userId: auth.state.userId,
        accountGeneration: AccountLocalDataCleaner.accountDataGeneration,
        ownerRoute: ModalRoute.of(context),
      );
    } catch (_) {
      return null;
    }
  }

  bool isValid(BuildContext context) {
    if (leaseCaptureFailed) return false;
    if (auth.state.isLoggedIn && sessionLease == null) return false;
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
      accountGeneration,
    )) {
      return false;
    }
    if (ownerRoute != null && !ownerRoute!.isActive) {
      return false;
    }
    try {
      final currentAuth = context.read<AuthProvider>();
      if (!identical(currentAuth, auth)) return false;
      if (sessionLease != null &&
          !currentAuth.isSessionLeaseCurrent(sessionLease!)) {
        return false;
      }
      final currentShare = context.read<ShareProvider>();
      if (!identical(currentShare, share)) return false;

      // Learn first nonempty ID once, allowing legacy hydration; reject later replacement
      final currentUserId = _normalizeUserId(currentAuth.state.userId);
      if (_userId == null) {
        if (currentUserId != null) {
          _userId = currentUserId;
        }
      } else {
        if (currentUserId != _userId) return false;
      }

      return true;
    } catch (_) {
      return false;
    }
  }
}

class _MentionContextBlock extends StatelessWidget {
  final String targetId;
  final String commentId;
  final List<WorkspaceComment> comments;
  final AppLocale? locale;

  const _MentionContextBlock({
    required this.targetId,
    required this.commentId,
    required this.comments,
    this.locale,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveLocale = locale ?? I18n.current;
    final cs = Theme.of(context).colorScheme;
    final focused = comments
        .where((comment) => comment.id == commentId)
        .toList();
    final visible = focused.isEmpty ? comments.take(3).toList() : focused;
    return AppSurfaceCard(
      padding: const EdgeInsets.all(12),
      color: cs.primary.withValues(alpha: 0.06),
      border: Border.all(
        color: cs.primary.withValues(alpha: 0.22),
        width: 0.45,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(Icons.alternate_email, size: 16, color: cs.primary),
              Text(
                ShareUiCopy.mentionContextTitle(effectiveLocale),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.normal,
                ),
              ),
              AppStatusBadge(label: targetId, color: cs.primary),
            ],
          ),
          const SizedBox(height: 8),
          if (visible.isEmpty)
            Text(
              ShareUiCopy.mentionContextEmpty(targetId, effectiveLocale),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.onSurface.withValues(alpha: 0.66),
              ),
            )
          else
            ...visible.map(
              (comment) => _CommentTile(comment, locale: effectiveLocale),
            ),
        ],
      ),
    );
  }
}

class _LeaderboardTile extends StatelessWidget {
  final int rank;
  final WorkspaceLeaderboardEntry entry;
  final AppLocale? locale;

  const _LeaderboardTile({
    required this.rank,
    required this.entry,
    this.locale,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveLocale = locale ?? I18n.current;
    final cs = Theme.of(context).colorScheme;
    final percent = (entry.completionRate * 100).round();
    final roleLabel = entry.role.labelFor(effectiveLocale);
    final subtitle = ShareUiCopy.leaderboardSubtitle(
      roleLabel,
      entry.assigned,
      entry.completed,
      effectiveLocale,
    );
    final leadingWidget = Stack(
      clipBehavior: Clip.none,
      children: [
        _IdentityAvatar(
          userId: entry.userId,
          username: entry.username,
          role: entry.role,
          locale: effectiveLocale,
          radius: 16,
        ),
        Positioned(right: -4, bottom: -3, child: _RankBadge(rank: rank)),
      ],
    );

    final trailingWidget = Text(
      '$percent%',
      style: TextStyle(
        color: cs.primary,
        fontWeight: FontWeight.normal,
        fontSize: 13,
      ),
    );

    final nameText = Text(
      entry.username.isEmpty ? entry.userId : entry.username,
    );

    final subtitleText = Text(subtitle, style: const TextStyle(fontSize: 11));

    final mediaWidth = MediaQuery.sizeOf(context).width;
    final textScaler = MediaQuery.textScalerOf(context);
    final isStacked = mediaWidth < 480 || textScaler.scale(14) >= 20;

    if (isStacked) {
      return ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [leadingWidget, trailingWidget],
            ),
            const SizedBox(height: 6),
            nameText,
          ],
        ),
        subtitle: subtitleText,
      );
    }

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: leadingWidget,
      title: nameText,
      subtitle: subtitleText,
      trailing: trailingWidget,
    );
  }
}

extension _IterableMapIndexed<E> on Iterable<E> {
  Iterable<T> mapIndexed<T>(T Function(int index, E item) convert) sync* {
    var index = 0;
    for (final item in this) {
      yield convert(index, item);
      index++;
    }
  }
}

class _CommentTile extends StatelessWidget {
  final WorkspaceComment comment;
  final AppLocale? locale;

  const _CommentTile(this.comment, {this.locale});

  @override
  Widget build(BuildContext context) {
    final effectiveLocale = locale ?? I18n.current;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: _IdentityAvatar(
        userId: comment.authorUserId,
        username: comment.authorName,
        locale: effectiveLocale,
        radius: 16,
      ),
      title: Text(comment.body),
      subtitle: Text(
        '${comment.authorName.isEmpty ? comment.authorUserId : comment.authorName} · ${_formatShortTime(comment.createdAt)}',
        style: const TextStyle(fontSize: 11),
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  final WorkspaceActivity activity;
  final AppLocale? locale;

  const _ActivityTile(this.activity, {this.locale});

  @override
  Widget build(BuildContext context) {
    final effectiveLocale = locale ?? I18n.current;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.bolt_outlined, size: 18),
      title: Text(
        '${activity.actorName} ${activity.labelFor(effectiveLocale)}',
      ),
      subtitle: Text(
        _formatShortTime(activity.createdAt),
        style: const TextStyle(fontSize: 11),
      ),
    );
  }
}

class _EmptyCollaborationLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _EmptyCollaborationLine({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: color)),
          ),
        ],
      ),
    );
  }
}

String _formatShortTime(DateTime value) {
  return I18nDateFormat.shortDateTime(value);
}

class _MemberChip extends StatelessWidget {
  final WorkspaceMember member;
  final Workspace workspace;
  final AppLocale? locale;

  const _MemberChip({
    required this.member,
    required this.workspace,
    this.locale,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveLocale = locale ?? I18n.current;
    final cs = Theme.of(context).colorScheme;
    final mediaWidth = MediaQuery.sizeOf(context).width;
    final maxChipWidth = math.max(160.0, mediaWidth - 48.0);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxChipWidth),
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.16),
            width: 0.45,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _WorkspaceMemberAvatar(
              member: member,
              radius: 12,
              locale: effectiveLocale,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 5,
                runSpacing: 4,
                children: [
                  Text(
                    _memberName(member, effectiveLocale),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                  _MemberRoleBadge(role: member.role, locale: effectiveLocale),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberAvatarStack extends StatelessWidget {
  final List<WorkspaceMember> members;
  final AppLocale? locale;

  const _MemberAvatarStack({required this.members, this.locale});

  @override
  Widget build(BuildContext context) {
    final visible = members.take(5).toList(growable: false);
    final extra = members.length - visible.length;
    return SizedBox(
      height: 28,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < visible.length; i++)
            Positioned(
              left: i * 20,
              top: 0,
              child: _WorkspaceMemberAvatar(
                member: visible[i],
                radius: 14,
                showRoleRing: visible[i].role == WorkspaceRole.owner,
                locale: locale,
              ),
            ),
          if (extra > 0)
            Positioned(
              left: visible.length * 20,
              top: 0,
              child: _ExtraMemberAvatar(count: extra),
            ),
        ],
      ),
    );
  }
}

class _WorkspaceMemberAvatar extends StatelessWidget {
  final WorkspaceMember member;
  final double radius;
  final bool showRoleRing;
  final AppLocale? locale;

  const _WorkspaceMemberAvatar({
    required this.member,
    required this.radius,
    this.showRoleRing = false,
    this.locale,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveLocale = locale ?? I18n.current;
    final cs = Theme.of(context).colorScheme;
    final color = _memberColor(
      member.userId.isEmpty ? member.username : member.userId,
    );
    final ringColor = member.role == WorkspaceRole.owner
        ? cs.primary
        : cs.outlineVariant;
    return Tooltip(
      message:
          '${_memberName(member, effectiveLocale)} · ${member.role.labelFor(effectiveLocale)}',
      child: Container(
        padding: EdgeInsets.all(showRoleRing ? 1.5 : 1),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: cs.surface,
          border: Border.all(
            color: showRoleRing ? ringColor : cs.surface,
            width: 0.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: CircleAvatar(
          radius: radius,
          backgroundColor: color.withValues(alpha: 0.16),
          child: Text(
            _memberInitial(member, effectiveLocale),
            style: TextStyle(
              fontSize: radius <= 12 ? 10 : 11,
              fontWeight: FontWeight.normal,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

class _IdentityAvatar extends StatelessWidget {
  final String userId;
  final String username;
  final WorkspaceRole? role;
  final AppLocale? locale;
  final double radius;

  const _IdentityAvatar({
    required this.userId,
    required this.username,
    this.role,
    this.locale,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveLocale = locale ?? I18n.current;
    final cs = Theme.of(context).colorScheme;
    final color = _memberColor(userId.isEmpty ? username : userId);
    final name = _identityName(userId, username, effectiveLocale);
    final tooltipMessage = role == null
        ? name
        : '$name · ${role!.labelFor(effectiveLocale)}';
    return Tooltip(
      message: tooltipMessage,
      child: Container(
        padding: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: cs.surface,
          border: Border.all(color: cs.surface, width: 0.45),
        ),
        child: CircleAvatar(
          radius: radius,
          backgroundColor: color.withValues(alpha: 0.16),
          child: Text(
            _identityInitial(userId, username, effectiveLocale),
            style: TextStyle(
              fontSize: radius <= 14 ? 10 : 11,
              fontWeight: FontWeight.normal,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  final int rank;

  const _RankBadge({required this.rank});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final highlighted = rank <= 3;
    final background = highlighted
        ? Color.alphaBlend(
            DesignTokens.defaultWarning.withValues(
              alpha: isDark ? 0.22 : 0.16,
            ),
            cs.surface,
          )
        : cs.primaryContainer;
    final color = highlighted
        ? appReadableForeground(background, DesignTokens.defaultWarning)
        : appReadableForeground(background, cs.onPrimaryContainer);
    return Container(
      width: 17,
      height: 17,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        shape: BoxShape.circle,
        border: Border.all(
          color: cs.surface.withValues(alpha: 0.86),
          width: 0.45,
        ),
      ),
      child: Text(
        '$rank',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.normal,
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _ExtraMemberAvatar extends StatelessWidget {
  final int count;

  const _ExtraMemberAvatar({required this.count});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: cs.surface,
        border: Border.all(color: cs.surface, width: 0.45),
      ),
      child: CircleAvatar(
        radius: 14,
        backgroundColor: cs.surfaceContainerHighest,
        child: Text(
          '+$count',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.normal,
            color: cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _MemberRoleBadge extends StatelessWidget {
  final WorkspaceRole role;
  final AppLocale? locale;

  const _MemberRoleBadge({required this.role, this.locale});

  @override
  Widget build(BuildContext context) {
    final effectiveLocale = locale ?? I18n.current;
    final cs = Theme.of(context).colorScheme;
    final color = switch (role) {
      WorkspaceRole.owner => cs.primary,
      WorkspaceRole.editor => DesignTokens.defaultAccent,
      WorkspaceRole.viewer => cs.onSurfaceVariant,
    };
    final icon = switch (role) {
      WorkspaceRole.owner => Icons.workspace_premium_outlined,
      WorkspaceRole.editor => Icons.edit_outlined,
      WorkspaceRole.viewer => Icons.visibility_outlined,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(
            role.labelFor(effectiveLocale),
            style: TextStyle(fontSize: 10.5, color: color),
          ),
        ],
      ),
    );
  }
}

String _memberName(WorkspaceMember member, [AppLocale? locale]) {
  return _identityName(member.userId, member.username, locale);
}

String _memberInitial(WorkspaceMember member, [AppLocale? locale]) {
  return _identityInitial(member.userId, member.username, locale);
}

String _identityName(String userId, String username, [AppLocale? locale]) {
  final name = username.trim();
  if (name.isNotEmpty) return name;
  final id = userId.trim();
  return id.isEmpty ? ShareUiCopy.defaultMemberName(locale) : id;
}

String _identityInitial(String userId, String username, [AppLocale? locale]) {
  final source = _identityName(userId, username, locale);
  if (source.isEmpty) return '?';
  return String.fromCharCode(source.runes.first).toUpperCase();
}

Color _memberColor(String seed) {
  const colors = <Color>[
    Color(0xFF2563EB),
    Color(0xFF059669),
    Color(0xFFDC2626),
    Color(0xFF7C3AED),
    Color(0xFF0891B2),
    Color(0xFF9333EA),
    Color(0xFFCA8A04),
    Color(0xFFDB2777),
  ];
  final value = seed.runes.fold<int>(0, (sum, code) => sum + code);
  return colors[value.abs() % colors.length];
}
