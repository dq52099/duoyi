import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/account_preference_writes.dart';
import '../core/announcement_ui_copy.dart';
import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../providers/auth_provider.dart';
import '../services/account_local_data_cleaner.dart';
import '../services/api_client.dart';
import '../services/settings_action_origin.dart';
import 'package:duoyi/desktop_web/desktop_embedded_scope.dart';

import '../widgets/brand_background.dart'
    show BrandBackground, BrandRouteSurface, LocaleStatePreservingRoute;
import '../widgets/empty_state.dart';
import '../widgets/surface_components.dart';

class AnnouncementsScreen extends StatefulWidget
    implements LocaleStatePreservingRoute {
  const AnnouncementsScreen({super.key});

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

typedef _AnnouncementAccount = ({
  AuthProvider auth,
  ApiClient client,
  int session,
  int generation,
  String? userId,
  String? token,
  bool changing,
  bool blocked,
});

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  bool _loading = false;
  List<Map<String, dynamic>> _items = [];
  Object? _error;
  int _loadSerial = 0;
  _AnnouncementAccount? _account;

  @override
  void initState() {
    super.initState();
    I18n.localeListenable.addListener(_onLocaleChanged);
    AccountLocalDataCleaner.accountDataGenerationListenable.addListener(
      _onAccountInvalidated,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAccount(context.watch<AuthProvider>());
  }

  @override
  void dispose() {
    _loadSerial++;
    I18n.localeListenable.removeListener(_onLocaleChanged);
    AccountLocalDataCleaner.accountDataGenerationListenable.removeListener(
      _onAccountInvalidated,
    );
    super.dispose();
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  _AnnouncementAccount _captureAccount(AuthProvider auth) => (
    auth: auth,
    client: auth.client,
    session: auth.sessionGeneration,
    generation: AccountLocalDataCleaner.accountDataGeneration,
    userId: auth.state.userId,
    token: auth.state.token,
    changing: auth.isAccountTransitionInProgress,
    blocked: auth.isLocalAccountDataBlocked,
  );

  bool _isCurrentAccount(_AnnouncementAccount account) =>
      mounted &&
      account == _account &&
      account == _captureAccount(context.read<AuthProvider>());

  void _onAccountInvalidated() {
    if (!mounted) return;
    setState(() => _syncAccount(context.read<AuthProvider>()));
  }

  void _syncAccount(AuthProvider auth) {
    final account = _captureAccount(auth);
    if (account == _account) return;
    _account = account;
    final serial = ++_loadSerial;
    _items = [];
    _error = null;
    _loading = false;
    if (account.changing || account.blocked) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isCurrentAccount(account) || serial != _loadSerial) return;
      _load(account, SettingsActionOrigin(context));
    });
  }

  Future<void> _load(
    _AnnouncementAccount account,
    SettingsActionOrigin origin,
  ) async {
    if (!_isCurrentAccount(account) ||
        account.changing ||
        account.blocked ||
        !origin.isCurrent()) {
      return;
    }
    final serial = ++_loadSerial;
    bool mayApply() =>
        _isCurrentAccount(account) &&
        serial == _loadSerial &&
        origin.isCurrent();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Reads wait outside tracked writes; cleanup invalidates the captured
      // account before any request can be dispatched for its replacement.
      await AccountPreferenceWrites.waitForBoundary();
      if (!mayApply()) return;
      final list = await account.client.getList('/api/announcements');
      // Eager validation keeps malformed rows inside the load error path.
      final items = list
          .map((item) {
            if (item is! Map<String, dynamic>) {
              throw const FormatException('Invalid announcement row');
            }
            return Map<String, dynamic>.of(item);
          })
          .toList(growable: false);
      if (!mayApply()) return;
      _items = items;
    } catch (e) {
      if (mayApply()) _error = e;
    } finally {
      // Even a covered route must release its own spinner. Older requests
      // cannot stop the loading indicator owned by a newer refresh.
      if (mounted && serial == _loadSerial) {
        setState(() => _loading = false);
      }
    }
  }

  Color _levelColor(String level) {
    switch (level) {
      case 'warning':
        return DesignTokens.defaultWarning;
      case 'critical':
        return Theme.of(context).colorScheme.error;
      default:
        return Theme.of(context).colorScheme.primary;
    }
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

  String _levelLabel(String level) {
    switch (level) {
      case 'warning':
        return I18n.tr('announcement.level.warning');
      case 'critical':
        return I18n.tr('announcement.level.critical');
      default:
        return I18n.tr('announcement.level.info');
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = _account!;
    final origin = SettingsActionOrigin(context);
    final accountReady = !account.changing && !account.blocked;
    Future<void> refresh() => _load(account, origin);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final surfaceStyle = appSurfaceStyleOf(context);
    final isLiquidGlass = surfaceStyle == AppSurfaceStyle.liquidGlass;
    final routeBackground = isDark
        ? cs.surface
        : cs.surfaceContainerLowest;
    final cardBackdrop = isDark ? cs.surface : theme.scaffoldBackgroundColor;
    final cardBg = surfaceStyle?.cardFillColor != null
        ? Color.alphaBlend(surfaceStyle!.cardFillColor!, cardBackdrop)
        : cs.surface;
    final heroBg = Color.alphaBlend(
      cs.primary.withValues(alpha: 0.12),
      cardBg,
    );
    final heroExplanationColor = _resolveAccessibleForeground(
      heroBg,
      appSecondaryDescriptionColor(context, isHero: true),
      isDark: isDark,
    );

    final scaffold = Scaffold(
      backgroundColor: isLiquidGlass ? Colors.transparent : routeBackground,
      appBar: AppBar(
        title: Text(I18n.tr('announcement.title')),
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
        backgroundColor: routeBackground.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: AnnouncementUiCopy.refresh,
            onPressed: accountReady && !_loading ? refresh : null,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: AppSecondaryControlTheme(
        child: RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            key: const PageStorageKey('announcements_list'),
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
                        Icons.campaign_outlined,
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
                            I18n.tr('announcement.center'),
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.normal,
                                  color: cs.onSurface,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            I18n.tr('announcement.subtitle'),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: heroExplanationColor,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              AppSectionHeader(
                title: I18n.tr('announcement.latest'),
                subtitle: I18n.tr('announcement.pull_to_refresh'),
                padding: EdgeInsets.zero,
              ),
              const SizedBox(height: 8),
              if (!accountReady)
                AppInfoBanner(
                  icon: Icons.account_circle_outlined,
                  message: AnnouncementUiCopy.accountChanging,
                  color: cs.primary,
                )
              else if (_loading)
                Padding(
                  key: const ValueKey('announcements_loading'),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: _AnnouncementLoading(hasItems: _items.isNotEmpty),
                ),
              if (_error != null) ...[
                AppSurfaceCard(
                  key: const ValueKey('announcements_refresh_error'),
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        AnnouncementUiCopy.errorMessage(
                          _error!,
                          hasItems: _items.isNotEmpty,
                        ),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: cs.onSurface,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          key: const ValueKey('announcements_retry'),
                          onPressed: accountReady && !_loading ? refresh : null,
                          icon: const Icon(Icons.refresh, size: 18),
                          label: Text(AnnouncementUiCopy.retry),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (accountReady && !_loading && _error == null && _items.isEmpty)
                EmptyState(
                  icon: Icons.campaign_outlined,
                  message: I18n.tr('announcement.empty'),
                  actionLabel: I18n.tr('announcement.refresh'),
                  onAction: refresh,
                ),
              if (_items.isNotEmpty)
                ..._items.map((a) {
                  final level = (a['level'] ?? 'info').toString();
                  final levelColor = _levelColor(level);
                  final pillBg = Color.alphaBlend(
                    levelColor.withValues(alpha: 0.14),
                    cardBg,
                  );
                  final pillFg = _resolveAccessibleForeground(
                    pillBg,
                    levelColor,
                    isDark: isDark,
                    minContrast: 5.5,
                  );
                  final titleText = (a['title'] ?? '').toString();
                  final titleStyle = Theme.of(context).textTheme.titleSmall
                      ?.copyWith(
                        fontWeight: FontWeight.normal,
                        color: cs.onSurface,
                      );
                  final bodyText = (a['body'] ?? '').toString();
                  final createdAtText = (a['created_at'] ?? '').toString();
                  final timestampPreferred =
                      appSecondaryDescriptionColor(context);
                  final timestampColor = _resolveAccessibleForeground(
                    cardBg,
                    timestampPreferred,
                    isDark: isDark,
                  );

                  return AppSurfaceCard(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final availableWidth = constraints.maxWidth;
                            final textScaler = MediaQuery.textScalerOf(context);
                            final badgeStyle = TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.normal,
                              color: pillFg,
                            );
                            final badgeLabel = _levelLabel(level);
                            final badgePainter = TextPainter(
                              text: TextSpan(
                                text: badgeLabel,
                                style: badgeStyle,
                              ),
                              textDirection: Directionality.of(context),
                              textScaler: textScaler,
                            )..layout();
                            final badgePillWidth = badgePainter.width + 16.0;
                            badgePainter.dispose();

                            final words =
                                RegExp(r'[A-Za-z0-9]+').allMatches(titleText);
                            double maxWordWidth = 0.0;
                            for (final match in words) {
                              final wordPainter = TextPainter(
                                text: TextSpan(
                                  text: match.group(0)!,
                                  style: titleStyle,
                                ),
                                textDirection: Directionality.of(context),
                                textScaler: textScaler,
                              )..layout();
                              if (wordPainter.width > maxWordWidth) {
                                maxWordWidth = wordPainter.width;
                              }
                              wordPainter.dispose();
                            }

                            final remainingWidth =
                                availableWidth - badgePillWidth - 8.0;
                            final bool separateLines =
                                remainingWidth < maxWordWidth ||
                                remainingWidth < 120.0 ||
                                badgePillWidth >= availableWidth * 0.55;

                            final badgeWidget = Container(
                              constraints: BoxConstraints(
                                maxWidth: availableWidth,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: levelColor.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                badgeLabel,
                                style: badgeStyle,
                              ),
                            );

                            final titleWidget = Text(
                              titleText,
                              style: titleStyle,
                            );

                            if (separateLines) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  badgeWidget,
                                  const SizedBox(height: 6),
                                  titleWidget,
                                ],
                              );
                            }

                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                badgeWidget,
                                const SizedBox(width: 8),
                                Expanded(child: titleWidget),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        Text(
                          bodyText,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: cs.onSurface.withValues(alpha: 0.74),
                                height: 1.5,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          createdAtText,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: timestampColor,
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

class _AnnouncementLoading extends StatelessWidget {
  const _AnnouncementLoading({required this.hasItems});

  final bool hasItems;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const LinearProgressIndicator(),
      const SizedBox(height: 8),
      Text(
        hasItems ? AnnouncementUiCopy.updating : AnnouncementUiCopy.loading,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
}
