/// 扩展功能：日历订阅 + 位置提醒 + 语言设置（Task T-* 集成 UI）。
///
/// 把 v2 阶段新增的三类"边缘能力"集中在一个 Tab 化页面里：
/// - 日历订阅：用户粘贴 .ics URL 即可让多仪日历显示外部日程；
/// - 位置提醒：手动录入坐标 + 半径 + 触发方向；
/// - 语言：在中 / 英 之间切换。
library;

import '../widgets/app_date_format.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/account_preference_writes.dart';
import '../core/design_tokens.dart';
import '../core/export_ui_copy.dart';
import '../core/i18n.dart';
import '../core/ics_subscription_storage.dart';
import '../services/settings_action_origin.dart';
import '../core/notification_ui_copy.dart';
import '../models/location_reminder.dart';
import '../providers/location_reminder_provider.dart';
import '../providers/notification_service.dart';
import '../services/calendar_sync_service.dart';
import '../services/location_geofence_service.dart';
import '../widgets/app_live_popup_menu_button.dart';
import '../widgets/brand_background.dart';
import '../widgets/surface_components.dart';
import '../widgets/controller_dialog.dart';

class IntegrationsScreen extends StatelessWidget
    implements LocaleStatePreservingRoute {
  final Uri? initialOAuthCallbackUri;

  const IntegrationsScreen({super.key, this.initialOAuthCallbackUri});

  @override
  Widget build(BuildContext context) {
    final needsCalendarSync = context.read<CalendarSyncProvider?>() == null;
    final needsLocationReminder =
        context.read<LocationReminderProvider?>() == null;
    final needsNotificationService =
        context.read<NotificationService?>() == null;
    final needsLocaleProvider = context.read<LocaleProvider?>() == null;
    if (needsCalendarSync ||
        needsLocationReminder ||
        needsNotificationService ||
        needsLocaleProvider) {
      return _IntegrationsProviderFallback(
        needsCalendarSync: needsCalendarSync,
        needsLocationReminder: needsLocationReminder,
        needsNotificationService: needsNotificationService,
        needsLocaleProvider: needsLocaleProvider,
        child: _IntegrationsScreenBody(
          initialOAuthCallbackUri: initialOAuthCallbackUri,
        ),
      );
    }
    return _IntegrationsScreenBody(
      initialOAuthCallbackUri: initialOAuthCallbackUri,
    );
  }
}

class _IntegrationsProviderFallback extends StatefulWidget {
  final bool needsCalendarSync;
  final bool needsLocationReminder;
  final bool needsNotificationService;
  final bool needsLocaleProvider;
  final Widget child;

  const _IntegrationsProviderFallback({
    required this.needsCalendarSync,
    required this.needsLocationReminder,
    required this.needsNotificationService,
    required this.needsLocaleProvider,
    required this.child,
  });

  @override
  State<_IntegrationsProviderFallback> createState() =>
      _IntegrationsProviderFallbackState();
}

class _IntegrationsProviderFallbackState
    extends State<_IntegrationsProviderFallback> {
  late final CalendarSyncProvider _calendarSync = CalendarSyncProvider();
  late final LocationReminderProvider _locationReminders =
      LocationReminderProvider();
  late final NotificationService _notificationService = NotificationService();
  late final LocaleProvider _localeProvider = LocaleProvider();

  @override
  void initState() {
    super.initState();
    if (widget.needsCalendarSync) {
      unawaited(_calendarSync.loadFromStorage());
    }
    if (widget.needsLocationReminder) {
      unawaited(_locationReminders.loadFromStorage());
    }
    if (widget.needsLocaleProvider) {
      unawaited(_localeProvider.loadFromStorage());
    }
  }

  @override
  void dispose() {
    _calendarSync.dispose();
    _locationReminders.dispose();
    _notificationService.dispose();
    _localeProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        if (widget.needsCalendarSync)
          ChangeNotifierProvider<CalendarSyncProvider>.value(
            value: _calendarSync,
          ),
        if (widget.needsLocationReminder)
          ChangeNotifierProvider<LocationReminderProvider>.value(
            value: _locationReminders,
          ),
        if (widget.needsNotificationService)
          ChangeNotifierProvider<NotificationService>.value(
            value: _notificationService,
          ),
        if (widget.needsLocaleProvider)
          ChangeNotifierProvider<LocaleProvider>.value(value: _localeProvider),
      ],
      child: widget.child,
    );
  }
}

class _IntegrationsScreenBody extends StatelessWidget {
  final Uri? initialOAuthCallbackUri;

  const _IntegrationsScreenBody({this.initialOAuthCallbackUri});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, _, _) {
        final cs = Theme.of(context).colorScheme;
        final routeBackground = Theme.of(context).brightness == Brightness.dark
            ? cs.surface
            : cs.surfaceContainerLowest;
        final surfaceStyle = appSurfaceStyleOf(context);
        final isLiquidGlass = surfaceStyle == AppSurfaceStyle.liquidGlass;
        final scaffold = DefaultTabController(
          length: 3,
          child: Scaffold(
            backgroundColor: isLiquidGlass
                ? Colors.transparent
                : routeBackground,
            appBar: AppBar(
              title: Text(NotificationUiCopy.integrationsTitle),
              titleTextStyle: appSecondaryRouteTitleTextStyle(context),
              backgroundColor: routeBackground.withValues(alpha: 0.96),
              surfaceTintColor: Colors.transparent,
              bottom: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelStyle: appSecondaryMenuItemTextStyle(context),
                unselectedLabelStyle: appSecondaryMenuItemTextStyle(context),
                labelPadding: const EdgeInsets.symmetric(horizontal: 12),
                indicatorSize: TabBarIndicatorSize.tab,
                tabs: [
                  Tab(height: 34, text: NotificationUiCopy.tabCalendar),
                  Tab(height: 34, text: NotificationUiCopy.tabLocation),
                  Tab(height: 34, text: NotificationUiCopy.tabLanguage),
                ],
              ),
            ),
            body: AppSecondaryControlTheme(
              child: TabBarView(
                children: [
                  _CalendarSubscriptionsTab(
                    initialOAuthCallbackUri: initialOAuthCallbackUri,
                  ),
                  _LocationRemindersTab(),
                  _LocaleTab(),
                ],
              ),
            ),
          ),
        );

        if (!isLiquidGlass) {
          return scaffold;
        }

        final hasBrandSurface =
            context.findAncestorWidgetOfExactType<BrandBackground>() != null ||
            context.findAncestorWidgetOfExactType<BrandRouteSurface>() != null;
        if (hasBrandSurface) {
          return scaffold;
        }
        return Material(
          color: routeBackground,
          child: BrandBackground(child: scaffold),
        );
      },
    );
  }
}

ButtonStyle _integrationOutlinedButtonStyle(BuildContext context) =>
    OutlinedButton.styleFrom(
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      minimumSize: const Size(0, 36),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      textStyle: appSecondaryMenuItemTextStyle(context),
    );

ButtonStyle _integrationFilledButtonStyle(BuildContext context) =>
    FilledButton.styleFrom(
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      minimumSize: const Size(0, 36),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      textStyle: appSecondaryMenuItemTextStyle(context),
    );

class _IntegrationActionStrip extends StatelessWidget {
  final List<Widget> children;

  const _IntegrationActionStrip({required this.children});

  @override
  Widget build(BuildContext context) {
    final spacedChildren = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) spacedChildren.add(const SizedBox(width: 5));
      spacedChildren.add(children[i]);
    }

    return SizedBox(
      key: const ValueKey('integration_action_strip'),
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: spacedChildren,
              ),
            ),
          );
        },
      ),
    );
  }
}

TextStyle _integrationHintTextStyle(
  BuildContext context, {
  double fontSize = 12,
  double alpha = 0.62,
}) {
  final cs = Theme.of(context).colorScheme;
  return (Theme.of(context).textTheme.bodySmall ?? const TextStyle()).copyWith(
    fontSize: fontSize,
    color: cs.onSurface.withValues(alpha: alpha),
    fontWeight: FontWeight.normal,
  );
}

TextStyle _integrationWarningTextStyle(BuildContext context) =>
    _integrationHintTextStyle(
      context,
      fontSize: 11,
    ).copyWith(color: Theme.of(context).colorScheme.tertiary);

TextStyle _integrationErrorTextStyle(BuildContext context) =>
    _integrationHintTextStyle(
      context,
      fontSize: 11,
    ).copyWith(color: Theme.of(context).colorScheme.error);

TextStyle _icsErrorTextStyle(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  final isLight = Theme.of(context).brightness == Brightness.light;
  final isGlass = appSurfaceStyleOf(context) == AppSurfaceStyle.liquidGlass;
  final color = isLight && isGlass
      ? Color.lerp(cs.error, Colors.black, 0.08)!
      : cs.error;
  return _integrationErrorTextStyle(context).copyWith(color: color);
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
  bool _reconciling = false;
  bool _globalRefreshing = false;
  int _reconcileOp = 0;
  int _globalRefreshOp = 0;

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

  Future<void> _reconcileStorage(
    BuildContext context,
    CalendarSyncProvider provider,
  ) async {
    if (_reconciling) return;
    final origin = SettingsActionOrigin(context);
    final initialGeneration = provider.icsLifetimeGeneration;
    final thisOp = ++_reconcileOp;
    setState(() => _reconciling = true);
    try {
      await provider.reconcileIcsStorage(
        isCurrent: () {
          if (!origin.isCurrent(checkRoute: true)) return false;
          if (!mounted) return false;
          try {
            if (!identical(context.read<CalendarSyncProvider>(), provider)) {
              return false;
            }
          } catch (_) {
            return false;
          }
          return provider.icsLifetimeGeneration == initialGeneration;
        },
      );
    } on AccountPreferenceWriteCanceled {
      return;
    } catch (_) {
      // Retain actionable recovery UI without exposing internals.
    } finally {
      if (mounted && thisOp == _reconcileOp) {
        setState(() => _reconciling = false);
      }
    }
  }

  Future<void> _handleGlobalRefresh(
    BuildContext context,
    CalendarSyncProvider provider,
  ) async {
    if (_globalRefreshing || provider.isSyncing) return;
    final origin = SettingsActionOrigin(context);
    final initialGeneration = provider.icsLifetimeGeneration;
    final thisOp = ++_globalRefreshOp;
    setState(() => _globalRefreshing = true);
    try {
      await provider.syncAll(
        isCurrent: () {
          if (!origin.isCurrent(checkRoute: true)) return false;
          if (!mounted || !context.mounted) return false;
          try {
            if (!identical(context.read<CalendarSyncProvider>(), provider)) {
              return false;
            }
          } catch (_) {
            return false;
          }
          return provider.icsLifetimeGeneration == initialGeneration;
        },
      );
    } on AccountPreferenceWriteCanceled {
      return;
    } catch (_) {
      // Catch under origin without crashing.
    } finally {
      if (mounted && thisOp == _globalRefreshOp) {
        setState(() => _globalRefreshing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CalendarSyncProvider>();
    final subs = provider.subscriptions;
    final oauthAccounts = provider.oauthAccounts;
    final isEn = NotificationUiCopy.isEn;
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AppSurfaceCard(
              padding: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.event_available, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            NotificationUiCopy.icsHeaderTitle,
                            style: const TextStyle(
                              fontWeight: FontWeight.normal,
                            ),
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
                    Text(
                      NotificationUiCopy.icsHeaderDescription,
                      style: _integrationHintTextStyle(context),
                    ),
                  ],
                ),
              ),
            ),
            if (provider.icsStorageNeedsReconciliation) ...[
              const SizedBox(height: 12),
              AppSurfaceCard(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: _icsErrorTextStyle(context).color,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isEn
                                ? 'Storage state is uncertain. Please recover storage before continuing.'
                                : '存储状态异常，请先恢复存储',
                            style: TextStyle(
                              color: _icsErrorTextStyle(context).color,
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _reconciling
                          ? null
                          : () => _reconcileStorage(context, provider),
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        children: [
                          if (_reconciling)
                            const SizedBox.square(
                              dimension: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          Text(isEn ? 'Recover Storage' : '恢复存储'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            _OAuthCalendarCard(provider: provider),
            const SizedBox(height: 12),
            for (final account in oauthAccounts)
              _OAuthCalendarTile(account: account),
            if (oauthAccounts.isNotEmpty) const SizedBox(height: 4),
            _CalDavWriteTargetCard(provider: provider),
            const SizedBox(height: 12),
            for (final s in subs)
              _SubscriptionTile(key: ValueKey(s.id), sub: s),
            if (subs.isEmpty && oauthAccounts.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    NotificationUiCopy.emptySubscriptions,
                    style: _integrationHintTextStyle(context, alpha: 0.50),
                  ),
                ),
              ),
            const SizedBox(height: 80),
          ],
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: SafeArea(
            top: false,
            child: Align(
              alignment: Alignment.bottomRight,
              child: _IntegrationActionStrip(
                children: [
                  if (provider.subscriptions.isNotEmpty ||
                      oauthAccounts.isNotEmpty)
                    FilledButton.tonalIcon(
                      onPressed: (provider.isSyncing || _globalRefreshing)
                          ? null
                          : () => _handleGlobalRefresh(context, provider),
                      style: _integrationFilledButtonStyle(context),
                      icon: const Icon(Icons.refresh),
                      label: Text(NotificationUiCopy.refreshAction),
                    ),
                  IconButton.filled(
                    tooltip: NotificationUiCopy.addIcsTooltip,
                    onPressed: () => _showAddDialog(context, provider),
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showAddDialog(
    BuildContext context,
    CalendarSyncProvider provider,
  ) async {
    final origin = SettingsActionOrigin(context);
    final initialGeneration = provider.icsLifetimeGeneration;
    BuildContext? modalContext;

    bool isDialogCurrent() {
      if (!origin.isCurrent(checkRoute: false)) return false;
      if (!context.mounted) return false;
      try {
        if (!identical(context.read<CalendarSyncProvider>(), provider)) {
          return false;
        }
      } catch (_) {
        return false;
      }
      if (provider.icsLifetimeGeneration != initialGeneration) return false;
      final mCtx = modalContext;
      if (mCtx == null || !mCtx.mounted) return false;
      final modalRoute = ModalRoute.of(mCtx);
      if (modalRoute == null || !modalRoute.isActive || !modalRoute.isCurrent) {
        return false;
      }
      return true;
    }

    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();

    var nameInvalid = false;
    var urlInvalid = false;
    var urlEmpty = false;

    var saving = false;
    var reconciling = false;
    var hasSaveError = false;
    var hadRejectedAttempt = false;
    var saveOp = 0;
    var reconcileOp = 0;

    String? submissionId;
    String? savedSubscriptionId;
    var dialogPopped = false;

    await showControllerDialog<void>(
      context: context,
      controllers: [nameCtrl, urlCtrl],
      builder: (dialogCtx) {
        modalContext = dialogCtx;
        return ValueListenableBuilder<AppLocale>(
          valueListenable: I18n.localeListenable,
          builder: (ctx, _, _) => ListenableBuilder(
            listenable: provider,
            builder: (ctx, _) => StatefulBuilder(
              builder: (ctx, setSt) {
                modalContext = ctx;

                final isEn = NotificationUiCopy.isEn;
                final nameError = nameInvalid
                    ? (isEn ? 'Please enter a subscription name' : '请填写订阅名称')
                    : null;
                final urlError = urlInvalid
                    ? (urlEmpty
                          ? (isEn ? 'Please enter an ICS URL' : '请填写 ICS URL')
                          : (isEn
                                ? 'Please enter a valid http/https address'
                                : '请输入有效的 http/https 地址'))
                    : null;

                Future<void> doReconcile() async {
                  if (saving || reconciling) return;
                  if (!isDialogCurrent()) return;
                  final thisOp = ++reconcileOp;
                  setSt(() => reconciling = true);
                  try {
                    await provider.reconcileIcsStorage(
                      isCurrent: isDialogCurrent,
                    );
                  } on AccountPreferenceWriteCanceled {
                    return;
                  } catch (_) {
                    // Retain actionable recovery UI without exposing internals.
                  } finally {
                    if (thisOp == reconcileOp &&
                        modalContext != null &&
                        modalContext!.mounted) {
                      setSt(() => reconciling = false);
                    }
                  }
                }

                Future<void> doSave() async {
                  if (saving || reconciling) return;
                  if (!isDialogCurrent()) return;
                  if (provider.icsStorageNeedsReconciliation) return;

                  final name = nameCtrl.text.trim();
                  final url = urlCtrl.text.trim();
                  final uri = Uri.tryParse(url);
                  final validUrl =
                      uri != null &&
                      uri.host.isNotEmpty &&
                      (uri.scheme == 'http' || uri.scheme == 'https');

                  final hasNameError = name.isEmpty;
                  final hasUrlError = url.isEmpty || !validUrl;

                  nameInvalid = hasNameError;
                  urlInvalid = hasUrlError;
                  urlEmpty = url.isEmpty;

                  if (hasNameError || hasUrlError) {
                    setSt(() {});
                    return;
                  }

                  final thisOp = ++saveOp;
                  saving = true;
                  hasSaveError = false;
                  setSt(() {});

                  submissionId ??= DateTime.now().millisecondsSinceEpoch
                      .toString();

                  final subscriptionToSave = IcsSubscription(
                    id: submissionId!,
                    name: name,
                    url: url,
                  );

                  try {
                    await provider.addSubscription(
                      subscriptionToSave,
                      isCurrent: isDialogCurrent,
                    );
                    if (!context.mounted ||
                        !origin.isCurrent(checkRoute: false) ||
                        !isDialogCurrent()) {
                      hadRejectedAttempt = true;
                    } else {
                      final mCtx = modalContext;
                      if (mCtx != null && mCtx.mounted) {
                        if (!dialogPopped) {
                          dialogPopped = true;
                          savedSubscriptionId = submissionId;
                          Navigator.of(mCtx).pop();
                        }
                      } else {
                        hadRejectedAttempt = true;
                      }
                    }
                  } on AccountPreferenceWriteCanceled {
                    hadRejectedAttempt = true;
                  } catch (_) {
                    hadRejectedAttempt = true;
                    if (isDialogCurrent()) {
                      hasSaveError = true;
                    }
                  } finally {
                    if (thisOp == saveOp &&
                        modalContext != null &&
                        modalContext!.mounted) {
                      setSt(() {
                        saving = false;
                      });
                    }
                  }
                }

                final media = MediaQuery.of(ctx);
                final cs = Theme.of(ctx).colorScheme;
                final isRetry = hasSaveError || hadRejectedAttempt;
                final disabledActionForeground = cs.onSurface.withValues(
                  alpha: 0.38,
                );
                final horizontalInset = media.size.width < 360 ? 12.0 : 20.0;
                final availableWidth = media.size.width - horizontalInset * 2;
                final effectiveMaxWidth = availableWidth.isFinite
                    ? availableWidth.clamp(0.0, 420.0).toDouble()
                    : 420.0;
                final dialogContentWidth = effectiveMaxWidth - 48.0;

                return Padding(
                  padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
                  child: AppDialog(
                    shiftForKeyboard: false,
                    title: Text(NotificationUiCopy.addSubscriptionDialogTitle),
                    content: SizedBox(
                      width: dialogContentWidth,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: nameCtrl,
                            decoration: InputDecoration(
                              labelText:
                                  NotificationUiCopy.subscriptionNameLabel,
                              errorText: nameError,
                              errorMaxLines: 3,
                            ),
                            autofocus: true,
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: urlCtrl,
                            decoration: InputDecoration(
                              labelText: NotificationUiCopy.icsUrlLabel,
                              hintText: 'https://...',
                              errorText: urlError,
                              errorMaxLines: 3,
                            ),
                            keyboardType: TextInputType.url,
                          ),
                          if (provider.icsStorageNeedsReconciliation) ...[
                            const SizedBox(height: 12),
                            Text(
                              isEn
                                  ? 'Storage state is uncertain. Please recover storage before retrying.'
                                  : '存储状态异常，重试前请先恢复存储',
                              style: TextStyle(
                                color: _icsErrorTextStyle(ctx).color,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Semantics(
                                button: true,
                                enabled: !(reconciling || saving),
                                label: reconciling
                                    ? (isEn ? 'Recovering storage…' : '正在恢复存储…')
                                    : null,
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    disabledForegroundColor:
                                        disabledActionForeground,
                                    side: BorderSide(
                                      color: (reconciling || saving)
                                          ? cs.outlineVariant.withValues(
                                              alpha: 0.16,
                                            )
                                          : cs.outlineVariant.withValues(
                                              alpha: 0.35,
                                            ),
                                      width: 0.4,
                                    ),
                                  ),
                                  onPressed: (reconciling || saving)
                                      ? null
                                      : () => doReconcile(),
                                  child: Wrap(
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    spacing: 8,
                                    runSpacing: 4,
                                    children: [
                                      if (reconciling) ...[
                                        SizedBox.square(
                                          dimension: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: cs.primary,
                                            semanticsLabel: isEn
                                                ? 'Recovering storage…'
                                                : '正在恢复存储…',
                                          ),
                                        ),
                                      ],
                                      Text(isEn ? 'Recover Storage' : '恢复存储'),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ] else if (hasSaveError) ...[
                            const SizedBox(height: 12),
                            Text(
                              isEn
                                  ? 'Failed to save subscription. Please retry.'
                                  : '保存订阅失败，请重试',
                              style: TextStyle(
                                color: _icsErrorTextStyle(ctx).color,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    actions: [
                      Semantics(
                        button: true,
                        enabled: !(saving || reconciling),
                        label: (saving || reconciling)
                            ? (isEn ? 'Waiting…' : '请稍候…')
                            : null,
                        child: TextButton(
                          style: TextButton.styleFrom(
                            disabledForegroundColor: disabledActionForeground,
                          ),
                          onPressed: (saving || reconciling)
                              ? null
                              : () {
                                  if (!isDialogCurrent()) return;
                                  Navigator.of(modalContext!).pop();
                                },
                          child: Text(I18n.tr('action.cancel')),
                        ),
                      ),
                      Semantics(
                        button: true,
                        enabled:
                            !(saving ||
                                reconciling ||
                                provider.icsStorageNeedsReconciliation),
                        label: saving
                            ? (isRetry
                                  ? (isEn ? 'Retrying…' : '正在重试…')
                                  : (isEn ? 'Saving…' : '正在保存…'))
                            : null,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            disabledForegroundColor: disabledActionForeground,
                          ),
                          onPressed:
                              (saving ||
                                  reconciling ||
                                  provider.icsStorageNeedsReconciliation)
                              ? null
                              : () => doSave(),
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              if (saving) ...[
                                SizedBox.square(
                                  dimension: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: cs.primary,
                                    semanticsLabel: isRetry
                                        ? (isEn ? 'Retrying…' : '正在重试…')
                                        : (isEn ? 'Saving…' : '正在保存…'),
                                  ),
                                ),
                              ],
                              Text(
                                isRetry
                                    ? I18n.tr('action.retry')
                                    : I18n.tr('action.add'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );

    if (savedSubscriptionId == null) return;

    if (!origin.isCurrent(checkRoute: true)) return;
    if (!context.mounted) return;
    try {
      if (!identical(context.read<CalendarSyncProvider>(), provider)) return;
    } catch (_) {
      return;
    }
    if (provider.icsLifetimeGeneration != initialGeneration) return;

    try {
      await provider.syncSubscription(
        savedSubscriptionId!,
        isCurrent: () {
          if (!origin.isCurrent(checkRoute: true)) return false;
          if (!context.mounted) return false;
          try {
            if (!identical(context.read<CalendarSyncProvider>(), provider)) {
              return false;
            }
          } catch (_) {
            return false;
          }
          return provider.icsLifetimeGeneration == initialGeneration;
        },
      );
    } catch (_) {
      // A failed refresh retains the saved row and offers Refresh retry, never another Save retry.
    }
  }
}

double _measureOAuthFeedbackReservedHeight(BuildContext context) {
  final media = MediaQuery.of(context);
  final theme = Theme.of(context);
  final textScaler = media.textScaler;
  final style = theme.snackBarTheme.contentTextStyle ??
      theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onInverseSurface,
      ) ??
      const TextStyle(fontSize: 14);

  final copies = [
    NotificationUiCopy.authUrlCopied,
    NotificationUiCopy.openAuthFailed,
  ];

  final double horizontalPadding = 32.0 + 30.0;
  final double maxTextWidth =
      (media.size.width - horizontalPadding).clamp(80.0, double.infinity);

  double maxTextHeight = 0.0;
  for (final copy in copies) {
    final painter = TextPainter(
      text: TextSpan(text: copy, style: style),
      textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
      textScaler: textScaler,
    )..layout(maxWidth: maxTextWidth);
    if (painter.height > maxTextHeight) {
      maxTextHeight = painter.height;
    }
    painter.dispose();
  }

  const double verticalOverhead = 28.0 + 15.0 + 8.0;
  return maxTextHeight + verticalOverhead;
}

class _OAuthCalendarCard extends StatelessWidget {
  final CalendarSyncProvider provider;

  const _OAuthCalendarCard({required this.provider});

  @override
  Widget build(BuildContext context) {
    final hasAccounts = provider.oauthAccounts.isNotEmpty;
    return AppSurfaceCard(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
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
                Expanded(
                  child: Text(
                    NotificationUiCopy.oauthCardTitle,
                    style: const TextStyle(fontWeight: FontWeight.normal),
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
            Text(
              NotificationUiCopy.oauthCardDescription,
              style: _integrationHintTextStyle(context),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: () => showOAuthDialog(context, provider),
                style: _integrationFilledButtonStyle(context),
                icon: const Icon(Icons.add_link, size: 16),
                label: Text(NotificationUiCopy.addAccountAction),
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
            SnackBar(
              content: _RetainedFeedbackText(
                () => NotificationUiCopy.oauthStateMismatch,
              ),
            ),
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

    final ok = await showControllerDialog<bool>(
      context: context,
      controllers: [
        nameCtrl,
        clientIdCtrl,
        clientSecretCtrl,
        redirectCtrl,
        calendarIdCtrl,
        codeCtrl,
      ],
      builder: (dialogCtx) => ScaffoldMessenger(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          resizeToAvoidBottomInset: false,
          body: ValueListenableBuilder<AppLocale>(
            valueListenable: I18n.localeListenable,
            builder: (ctx, _, _) => StatefulBuilder(
              builder: (dialogContext, setState) {
                final authUri = buildAuthUri();
                final reservedHeight =
                    _measureOAuthFeedbackReservedHeight(dialogContext);
                final media = MediaQuery.of(dialogContext);
                final adjustedMedia = media.copyWith(
                  size: Size(
                    media.size.width,
                    (media.size.height - reservedHeight).clamp(
                      0.0,
                      media.size.height,
                    ),
                  ),
                );
                return Padding(
                  padding: EdgeInsets.only(bottom: reservedHeight),
                  child: MediaQuery(
                    data: adjustedMedia,
                    child: Center(
                      child: AppDialog(
                        title: Text(NotificationUiCopy.addOauthDialogTitle),
                        maxWidth: 560,
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: AppSecondaryControlTheme(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppDropdownField<OAuthCalendarProvider>(
                          initialValue: selectedProvider,
                          decoration: InputDecoration(
                            labelText: NotificationUiCopy.providerLabel,
                          ),
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
                          decoration: InputDecoration(
                            labelText: NotificationUiCopy.displayNameLabel,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: clientIdCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Client ID',
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: clientSecretCtrl,
                          decoration: InputDecoration(
                            labelText:
                                NotificationUiCopy.clientSecretOptionalLabel,
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
                              Text(
                                NotificationUiCopy.authUrlSectionTitle,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.normal,
                                ),
                              ),
                              const SizedBox(height: 6),
                              SelectableText(
                                authUri?.toString() ??
                                    NotificationUiCopy.authUrlPlaceholder,
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
                                            await savePendingAuthorization(
                                              authUri,
                                            );
                                            if (!dialogContext.mounted) return;
                                            ScaffoldMessenger.of(
                                              dialogContext,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: _RetainedFeedbackText(
                                                  () => NotificationUiCopy
                                                      .authUrlCopied,
                                                ),
                                              ),
                                            );
                                          },
                                    style: _integrationOutlinedButtonStyle(
                                      context,
                                    ),
                                    icon: const Icon(Icons.copy, size: 16),
                                    label: Text(NotificationUiCopy.copyAction),
                                  ),
                                  FilledButton.tonalIcon(
                                    onPressed: authUri == null
                                        ? null
                                        : () async {
                                            await savePendingAuthorization(
                                              authUri,
                                            );
                                            final opened = await launchUrl(
                                              authUri,
                                              mode: LaunchMode
                                                  .externalApplication,
                                            );
                                            if (!dialogContext.mounted) return;
                                            if (!opened) {
                                              ScaffoldMessenger.of(
                                                dialogContext,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content:
                                                      _RetainedFeedbackText(
                                                        () => NotificationUiCopy
                                                            .openAuthFailed,
                                                      ),
                                                ),
                                              );
                                            }
                                          },
                                    style: _integrationFilledButtonStyle(
                                      context,
                                    ),
                                    icon: const Icon(
                                      Icons.open_in_new,
                                      size: 16,
                                    ),
                                    label: Text(NotificationUiCopy.openAction),
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
                          decoration: InputDecoration(
                            labelText: NotificationUiCopy.authCodeLabel,
                            hintText: NotificationUiCopy.authCodeHint,
                          ),
                        ),
                      ],
                    ),
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
                  child: Text(NotificationUiCopy.saveAndSyncAction),
                ),
              ],
            ))));
          },
        ),
      ),
    )));

    final displayName = nameCtrl.text.trim();
    final clientId = clientIdCtrl.text.trim();
    final redirectUri = redirectCtrl.text.trim();
    final authorizationCode = codeCtrl.text.trim();
    final clientSecret = clientSecretCtrl.text.trim();
    final calendarId = calendarIdCtrl.text.trim();
    if (ok != true) return;
    if (displayName.isEmpty ||
        clientId.isEmpty ||
        redirectUri.isEmpty ||
        authorizationCode.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: _RetainedFeedbackText(
            () => NotificationUiCopy.oauthFieldsRequired,
          ),
        ),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: _RetainedFeedbackText(
            () => NotificationUiCopy.oauthConnected,
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: _RetainedFeedbackText(
            () => NotificationUiCopy.formatOauthConnectError(e),
          ),
        ),
      );
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
          '${account.provider.label} · '
          '${account.enabled ? NotificationUiCopy.statusActive : NotificationUiCopy.statusPaused} · '
          '${account.calendarId.isEmpty ? "primary" : account.calendarId}'
          '${account.lastSyncedAt == null ? "" : " · ${NotificationUiCopy.lastSyncedAt(AppDateFormat.fullDateTime(context, account.lastSyncedAt!))}"}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11),
        ),
        trailing: AppLivePopupMenuButton<String>(
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
              child: ValueListenableBuilder<AppLocale>(
                valueListenable: I18n.localeListenable,
                builder: (_, _, _) => AppSecondaryMenuText(
                  account.enabled
                      ? NotificationUiCopy.menuPause
                      : NotificationUiCopy.menuResume,
                ),
              ),
            ),
            PopupMenuItem(
              value: 'sync',
              child: ValueListenableBuilder<AppLocale>(
                valueListenable: I18n.localeListenable,
                builder: (_, _, _) =>
                    AppSecondaryMenuText(NotificationUiCopy.menuSync),
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              child: ValueListenableBuilder<AppLocale>(
                valueListenable: I18n.localeListenable,
                builder: (_, _, _) =>
                    AppSecondaryMenuText(NotificationUiCopy.menuDelete),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CalDavWriteTargetCard extends StatelessWidget {
  final CalendarSyncProvider provider;

  const _CalDavWriteTargetCard({required this.provider});

  static TextStyle _calDavWarningStyle(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final isGlass = appSurfaceStyleOf(context) == AppSurfaceStyle.liquidGlass;
    final color = !isLight
        ? cs.tertiary
        : Color.lerp(cs.tertiary, Colors.black, isGlass ? 0.45 : 0.18)!;
    return _integrationWarningTextStyle(context).copyWith(color: color);
  }

  static TextStyle _calDavErrorStyle(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final isGlass = appSurfaceStyleOf(context) == AppSurfaceStyle.liquidGlass;
    final color = isLight && isGlass
        ? Color.lerp(cs.error, Colors.black, 0.08)!
        : cs.error;
    return _integrationErrorTextStyle(context).copyWith(color: color);
  }

  @override
  Widget build(BuildContext context) {
    final origin = SettingsActionOrigin(context);
    final revision = provider.writeTargetRevision;
    bool current() =>
        origin.isCurrent() &&
        identical(provider, context.read<CalendarSyncProvider>()) &&
        revision == provider.writeTargetRevision &&
        !provider.isUpdatingWriteTarget;
    final target = provider.writeTarget;
    final configured = target?.isConfigured == true;
    return AppSurfaceCard(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
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
                Expanded(
                  child: Text(
                    NotificationUiCopy.calDavTargetTitle,
                    style: const TextStyle(fontWeight: FontWeight.normal),
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
                  ? '${target!.enabled ? NotificationUiCopy.calDavVerified : NotificationUiCopy.calDavUnverified} · ${_conflictPolicyLabel(target.conflictPolicy)} · ${target.collectionUrl}'
                  : NotificationUiCopy.calDavConfigPrompt,
              style: _integrationHintTextStyle(context, alpha: 0.72),
            ),
            if (provider.lastCalDavConflicts.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                NotificationUiCopy.calDavConflictsSkipped(
                  provider.lastCalDavConflicts.length,
                ),
                style: _calDavWarningStyle(context),
              ),
            ],
            if (target?.lastTestedAt != null) ...[
              const SizedBox(height: 4),
              Text(
                NotificationUiCopy.lastTestedAt(
                  AppDateFormat.fullDateTime(context, target!.lastTestedAt!),
                ),
                style: _integrationHintTextStyle(
                  context,
                  fontSize: 11,
                  alpha: 0.66,
                ),
              ),
            ],
            if (provider.lastCalDavError != null) ...[
              const SizedBox(height: 6),
              Text(
                NotificationUiCopy.formatCalDavError(provider.lastCalDavError!),
                style: _calDavErrorStyle(context),
              ),
            ],
            const SizedBox(height: 10),
            _IntegrationActionStrip(
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    if (current()) _showCalDavDialog(context, provider);
                  },
                  style: _integrationOutlinedButtonStyle(context),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: Text(
                    configured
                        ? NotificationUiCopy.calDavEdit
                        : NotificationUiCopy.calDavConfigure,
                  ),
                ),
                if (configured)
                  OutlinedButton.icon(
                    onPressed: provider.isTestingWriteTarget
                        ? null
                        : () {
                            if (current()) {
                              _runTargetAction(
                                context,
                                provider,
                                provider.clearWriteTarget,
                              );
                            }
                          },
                    style: _integrationOutlinedButtonStyle(context),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: Text(NotificationUiCopy.calDavRemove),
                  ),
                OutlinedButton.icon(
                  onPressed: () {
                    if (current()) _showICloudCalDavDialog(context, provider);
                  },
                  style: _integrationOutlinedButtonStyle(context),
                  icon: const Icon(Icons.apple, size: 16),
                  label: const Text('iCloud'),
                ),
                FilledButton.tonalIcon(
                  onPressed: !configured || provider.isTestingWriteTarget
                      ? null
                      : () {
                          if (current()) {
                            provider.testWriteTarget(isCurrent: current);
                          }
                        },
                  style: _integrationFilledButtonStyle(context),
                  icon: const Icon(Icons.fact_check_outlined, size: 16),
                  label: Text(NotificationUiCopy.calDavTestWriteback),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _runTargetAction(
    BuildContext context,
    CalendarSyncProvider provider,
    Future<void> Function() action,
  ) async {
    final origin = SettingsActionOrigin(context);
    if (!origin.isCurrent() ||
        !identical(provider, context.read<CalendarSyncProvider>())) {
      return;
    }
    final revision = provider.writeTargetRevision + 1;
    try {
      await action();
    } on AccountPreferenceWriteCanceled {
      // Superseded configuration and account cleanup intentionally cancel.
    } catch (_) {
      if (!context.mounted ||
          !origin.isCurrent() ||
          !identical(provider, context.read<CalendarSyncProvider>()) ||
          provider.writeTargetRevision != revision) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: ValueListenableBuilder<AppLocale>(
            valueListenable: I18n.localeListenable,
            builder: (context, _, _) =>
                Text(ExportUiCopy.current().configurationFailed),
          ),
        ),
      );
    }
  }

  Future<void> _showCalDavDialog(
    BuildContext context,
    CalendarSyncProvider provider,
  ) async {
    final origin = SettingsActionOrigin(context);
    final revision = provider.writeTargetRevision;
    if (!origin.isCurrent()) return;
    final current = provider.writeTarget;
    final urlCtrl = TextEditingController(text: current?.collectionUrl ?? '');
    final authCtrl = TextEditingController(
      text: current?.authorizationHeader ?? '',
    );
    var conflictPolicy =
        current?.conflictPolicy ?? CalDavConflictPolicy.skipRemoteChanges;
    final ok = await showControllerDialog<bool>(
      context: context,
      controllers: [urlCtrl, authCtrl],
      builder: (ctx) => ValueListenableBuilder<AppLocale>(
        valueListenable: I18n.localeListenable,
        builder: (context, _, _) => StatefulBuilder(
          builder: (context, setState) => AppDialog(
            title: Text(NotificationUiCopy.calDavDialogTitle),
            content: AppSecondaryControlTheme(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: urlCtrl,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: NotificationUiCopy.collectionUrlLabel,
                      hintText:
                          'https://caldav.example.com/calendars/me/default/',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: authCtrl,
                    decoration: InputDecoration(
                      labelText: NotificationUiCopy.authHeaderLabel,
                      hintText: NotificationUiCopy.authHeaderHint,
                    ),
                  ),
                  const SizedBox(height: 12),
                  AppDropdownField<CalDavConflictPolicy>(
                    initialValue: conflictPolicy,
                    decoration: InputDecoration(
                      labelText: NotificationUiCopy.conflictPolicyLabel,
                    ),
                    items: [
                      DropdownMenuItem(
                        value: CalDavConflictPolicy.skipRemoteChanges,
                        child: Text(NotificationUiCopy.conflictPolicySkipItem),
                      ),
                      DropdownMenuItem(
                        value: CalDavConflictPolicy.overwriteRemote,
                        child: Text(
                          NotificationUiCopy.conflictPolicyOverwriteItem,
                        ),
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
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(I18n.tr('action.cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(NotificationUiCopy.saveAction),
              ),
            ],
          ),
        ),
      ),
    );
    final url = urlCtrl.text.trim();
    final auth = authCtrl.text.trim();
    if (ok != true || url.isEmpty || auth.isEmpty) return;
    if (!origin.isCurrent() ||
        !context.mounted ||
        !identical(provider, context.read<CalendarSyncProvider>()) ||
        provider.writeTargetRevision != revision) {
      return;
    }
    await _runTargetAction(
      context,
      provider,
      () => provider.saveWriteTarget(
        CalDavWriteTarget(
          collectionUrl: url,
          authorizationHeader: auth,
          enabled: current?.enabled == true,
          conflictPolicy: conflictPolicy,
          lastTestedAt: current?.lastTestedAt,
        ),
      ),
    );
  }

  Future<void> _showICloudCalDavDialog(
    BuildContext context,
    CalendarSyncProvider provider,
  ) async {
    final origin = SettingsActionOrigin(context);
    final revision = provider.writeTargetRevision;
    if (!origin.isCurrent()) return;
    final current = provider.writeTarget;
    final currentUrl = current?.collectionUrl ?? '';
    final urlCtrl = TextEditingController(
      text: currentUrl.startsWith('https://') ? currentUrl : '',
    );
    final appleIdCtrl = TextEditingController();
    final appPasswordCtrl = TextEditingController();
    var conflictPolicy =
        current?.conflictPolicy ?? CalDavConflictPolicy.skipRemoteChanges;
    final ok = await showControllerDialog<bool>(
      context: context,
      controllers: [urlCtrl, appleIdCtrl, appPasswordCtrl],
      builder: (ctx) => ValueListenableBuilder<AppLocale>(
        valueListenable: I18n.localeListenable,
        builder: (context, _, _) => StatefulBuilder(
          builder: (context, setState) => AppDialog(
            title: Text(NotificationUiCopy.iCloudDialogTitle),
            content: AppSecondaryControlTheme(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    NotificationUiCopy.isEn
                        ? 'Generate Basic Authorization with your Apple ID and App-Specific Password. Enter the iCloud CalDAV calendar collection URL.'
                        : CalDavCredentialHelper.iCloudSetupCopy,
                    style: _integrationHintTextStyle(context),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: urlCtrl,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: NotificationUiCopy.iCloudUrlLabel,
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
                    decoration: InputDecoration(
                      labelText: NotificationUiCopy.appSpecificPasswordLabel,
                    ),
                    obscureText: true,
                  ),
                  const SizedBox(height: 12),
                  AppDropdownField<CalDavConflictPolicy>(
                    initialValue: conflictPolicy,
                    decoration: InputDecoration(
                      labelText: NotificationUiCopy.conflictPolicyLabel,
                    ),
                    items: [
                      DropdownMenuItem(
                        value: CalDavConflictPolicy.skipRemoteChanges,
                        child: Text(NotificationUiCopy.conflictPolicySkipItem),
                      ),
                      DropdownMenuItem(
                        value: CalDavConflictPolicy.overwriteRemote,
                        child: Text(
                          NotificationUiCopy.conflictPolicyOverwriteItem,
                        ),
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
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(I18n.tr('action.cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(NotificationUiCopy.saveAction),
              ),
            ],
          ),
        ),
      ),
    );
    final url = urlCtrl.text.trim();
    final appleId = appleIdCtrl.text.trim();
    final appPassword = appPasswordCtrl.text.trim();
    if (ok != true || url.isEmpty || appleId.isEmpty || appPassword.isEmpty) {
      return;
    }
    if (!origin.isCurrent() ||
        !context.mounted ||
        !identical(provider, context.read<CalendarSyncProvider>()) ||
        provider.writeTargetRevision != revision) {
      return;
    }
    await _runTargetAction(
      context,
      provider,
      () => provider.saveWriteTarget(
        CalDavWriteTarget(
          collectionUrl: url,
          authorizationHeader: CalDavCredentialHelper.basicAuthorizationHeader(
            username: appleId,
            password: appPassword,
          ),
          enabled: false,
          conflictPolicy: conflictPolicy,
        ),
      ),
    );
  }

  String _conflictPolicyLabel(CalDavConflictPolicy policy) {
    return switch (policy) {
      CalDavConflictPolicy.skipRemoteChanges =>
        NotificationUiCopy.isEn ? 'Keep remote changes' : '远端变更不覆盖',
      CalDavConflictPolicy.overwriteRemote =>
        NotificationUiCopy.isEn ? 'Overwrite remote' : '覆盖远端',
    };
  }
}

enum _TileActionError { pauseFailed, resumeFailed, deleteFailed, storageFailed }

class _OpeningMenuActionRecord {
  final SettingsActionOrigin origin;
  final CalendarSyncProvider provider;
  final int lifetimeGeneration;
  final int sourceRevision;
  final IcsSubscription snapshot;
  final bool intendedPause;

  _OpeningMenuActionRecord({
    required this.origin,
    required this.provider,
    required this.lifetimeGeneration,
    required this.sourceRevision,
    required this.snapshot,
    required this.intendedPause,
  });
}

class _MenuRecordHolder {
  _OpeningMenuActionRecord? _record;
  bool _consumed = false;

  bool get isConsumed => _consumed;
  bool get hasRecord => _record != null;
  _OpeningMenuActionRecord? get record => _record;

  void bindRecord(_OpeningMenuActionRecord rec) {
    if (_consumed) return;
    _record = rec;
  }

  _OpeningMenuActionRecord? consume() {
    if (_consumed) return null;
    _consumed = true;
    return _record;
  }
}

class _ActionErrorState {
  final _TileActionError error;
  final CalendarSyncProvider provider;
  final SettingsActionOrigin origin;
  final int lifetimeGeneration;
  final int sourceRevision;
  final IcsSubscription snapshot;

  const _ActionErrorState({
    required this.error,
    required this.provider,
    required this.origin,
    required this.lifetimeGeneration,
    required this.sourceRevision,
    required this.snapshot,
  });
}

class _SubscriptionTile extends StatefulWidget {
  final IcsSubscription sub;
  const _SubscriptionTile({super.key, required this.sub});

  @override
  State<_SubscriptionTile> createState() => _SubscriptionTileState();
}

class _SubscriptionTileState extends State<_SubscriptionTile> {
  bool _busy = false;
  int _actionOp = 0;
  _ActionErrorState? _actionErrorState;
  _MenuRecordHolder? _activeMenuHolder;

  @override
  void dispose() {
    _activeMenuHolder?.consume();
    _activeMenuHolder = null;
    super.dispose();
  }

  void _recordMenuOpening(
    BuildContext context,
    _MenuRecordHolder holder,
    IcsSubscription sub,
  ) {
    if (holder.hasRecord || holder.isConsumed) return;
    final origin = SettingsActionOrigin(context);
    final p = context.read<CalendarSyncProvider>();
    holder.bindRecord(
      _OpeningMenuActionRecord(
        origin: origin,
        provider: p,
        lifetimeGeneration: p.icsLifetimeGeneration,
        sourceRevision: IcsSubscriptionStorage.sourceRevision(sub.id),
        snapshot: sub,
        intendedPause: sub.enabled,
      ),
    );
  }

  Future<void> _handleDirectRetry(
    BuildContext context,
    CalendarSyncProvider provider,
  ) async {
    if (_busy || provider.isSyncing) return;
    final origin = SettingsActionOrigin(context);
    final initialGeneration = provider.icsLifetimeGeneration;
    final initialRev = IcsSubscriptionStorage.sourceRevision(widget.sub.id);
    final snapshot = widget.sub;
    final thisOp = ++_actionOp;
    setState(() => _busy = true);

    bool hasFeedbackAuthority() {
      if (!origin.isCurrent(checkRoute: true)) return false;
      if (!mounted || !context.mounted) return false;
      try {
        if (!identical(context.read<CalendarSyncProvider>(), provider)) {
          return false;
        }
      } catch (_) {
        return false;
      }
      if (provider.icsLifetimeGeneration != initialGeneration) return false;
      return true;
    }

    bool isCurrent() {
      if (!hasFeedbackAuthority()) return false;
      if (IcsSubscriptionStorage.sourceRevision(snapshot.id) != initialRev) {
        return false;
      }
      return true;
    }

    try {
      await provider.syncSubscription(snapshot.id, isCurrent: isCurrent);
      if (hasFeedbackAuthority()) {
        setState(() => _actionErrorState = null);
      }
    } on AccountPreferenceWriteCanceled {
      return;
    } catch (_) {
      if (hasFeedbackAuthority()) {
        setState(() {
          _actionErrorState = _ActionErrorState(
            error: _TileActionError.storageFailed,
            provider: provider,
            origin: origin,
            lifetimeGeneration: initialGeneration,
            sourceRevision: IcsSubscriptionStorage.sourceRevision(snapshot.id),
            snapshot: snapshot,
          );
        });
      }
    } finally {
      if (mounted && thisOp == _actionOp) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _retryFailedAction(
    BuildContext context,
    CalendarSyncProvider provider,
    _ActionErrorState errorState,
  ) async {
    if (!mounted || !context.mounted) return;

    final CalendarSyncProvider currentProvider;
    try {
      currentProvider = context.read<CalendarSyncProvider>();
    } catch (_) {
      return;
    }

    if (!identical(currentProvider, provider) ||
        !identical(currentProvider, errorState.provider) ||
        !identical(_actionErrorState, errorState) ||
        _busy ||
        currentProvider.isSyncing) {
      return;
    }

    if (!errorState.origin.isCurrent(checkRoute: true) ||
        errorState.lifetimeGeneration !=
            currentProvider.icsLifetimeGeneration ||
        errorState.sourceRevision !=
            IcsSubscriptionStorage.sourceRevision(errorState.snapshot.id)) {
      return;
    }

    final origin = SettingsActionOrigin(context);
    final initialGeneration = currentProvider.icsLifetimeGeneration;
    final initialRev = IcsSubscriptionStorage.sourceRevision(
      errorState.snapshot.id,
    );

    final thisOp = ++_actionOp;
    setState(() => _busy = true);

    bool hasFeedbackAuthority() {
      if (!origin.isCurrent(checkRoute: true)) return false;
      if (!mounted || !context.mounted) return false;
      try {
        if (!identical(context.read<CalendarSyncProvider>(), currentProvider)) {
          return false;
        }
      } catch (_) {
        return false;
      }
      if (currentProvider.icsLifetimeGeneration != initialGeneration) {
        return false;
      }
      return true;
    }

    bool isActionCurrent() {
      if (!hasFeedbackAuthority()) return false;
      if (IcsSubscriptionStorage.sourceRevision(errorState.snapshot.id) !=
          initialRev) {
        return false;
      }
      return true;
    }

    try {
      if (currentProvider.icsStorageNeedsReconciliation) {
        await currentProvider.reconcileIcsStorage(isCurrent: isActionCurrent);
      } else {
        switch (errorState.error) {
          case _TileActionError.pauseFailed:
            final currentRows = currentProvider.subscriptions;
            final matchIndex = currentRows.indexWhere(
              (r) => r.id == errorState.snapshot.id,
            );
            if (matchIndex < 0) return;
            final currentSub = currentRows[matchIndex];
            if (!currentSub.enabled) return;
            await currentProvider.updateSubscription(
              currentSub.copyWith(enabled: false),
              isCurrent: isActionCurrent,
            );
            break;
          case _TileActionError.resumeFailed:
            final currentRows = currentProvider.subscriptions;
            final matchIndex = currentRows.indexWhere(
              (r) => r.id == errorState.snapshot.id,
            );
            if (matchIndex < 0) return;
            final currentSub = currentRows[matchIndex];
            if (currentSub.enabled) return;
            await currentProvider.updateSubscription(
              currentSub.copyWith(enabled: true),
              isCurrent: isActionCurrent,
            );
            break;
          case _TileActionError.deleteFailed:
            await currentProvider.removeSubscription(
              errorState.snapshot.id,
              isCurrent: isActionCurrent,
            );
            break;
          case _TileActionError.storageFailed:
            final currentRows = currentProvider.subscriptions;
            final matchIndex = currentRows.indexWhere(
              (r) => r.id == errorState.snapshot.id,
            );
            if (matchIndex < 0) return;
            await currentProvider.updateSubscription(
              currentRows[matchIndex],
              isCurrent: isActionCurrent,
            );
            break;
        }
      }
      if (hasFeedbackAuthority()) {
        setState(() => _actionErrorState = null);
      }
    } on AccountPreferenceWriteCanceled {
      return;
    } catch (_) {
      if (hasFeedbackAuthority()) {
        setState(() {
          _actionErrorState = _ActionErrorState(
            error: currentProvider.icsStorageNeedsReconciliation
                ? _TileActionError.storageFailed
                : errorState.error,
            provider: currentProvider,
            origin: origin,
            lifetimeGeneration: initialGeneration,
            sourceRevision: IcsSubscriptionStorage.sourceRevision(
              errorState.snapshot.id,
            ),
            snapshot: errorState.snapshot,
          );
        });
      }
    } finally {
      if (mounted && thisOp == _actionOp) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _executeMenuAction(
    String value,
    _OpeningMenuActionRecord record,
  ) async {
    if (!record.origin.isCurrent(checkRoute: true)) return;
    if (!mounted || !context.mounted) return;
    try {
      if (!identical(context.read<CalendarSyncProvider>(), record.provider)) {
        return;
      }
    } catch (_) {
      return;
    }
    if (record.provider.icsLifetimeGeneration != record.lifetimeGeneration) {
      return;
    }
    if (IcsSubscriptionStorage.sourceRevision(record.snapshot.id) !=
        record.sourceRevision) {
      return;
    }

    String action = value;
    if (action == 'toggle') {
      action = record.intendedPause ? 'pause' : 'resume';
    }

    final currentRows = record.provider.subscriptions;
    final matchIndex = currentRows.indexWhere(
      (r) => r.id == record.snapshot.id,
    );
    if (matchIndex < 0) return;
    final currentSub = currentRows[matchIndex];
    if (action == 'pause') {
      if (!currentSub.enabled || !record.intendedPause) {
        return;
      }
    } else if (action == 'resume') {
      if (currentSub.enabled || record.intendedPause) {
        return;
      }
    }

    if (_busy || record.provider.isSyncing) return;
    final thisOp = ++_actionOp;
    setState(() => _busy = true);

    bool hasFeedbackAuthority() {
      if (!record.origin.isCurrent(checkRoute: true)) return false;
      if (!mounted || !context.mounted) return false;
      try {
        if (!identical(context.read<CalendarSyncProvider>(), record.provider)) {
          return false;
        }
      } catch (_) {
        return false;
      }
      if (record.provider.icsLifetimeGeneration != record.lifetimeGeneration) {
        return false;
      }
      return true;
    }

    bool isActionCurrent() {
      if (!hasFeedbackAuthority()) return false;
      if (IcsSubscriptionStorage.sourceRevision(record.snapshot.id) !=
          record.sourceRevision) {
        return false;
      }
      return true;
    }

    try {
      if (action == 'pause') {
        await record.provider.updateSubscription(
          currentSub.copyWith(enabled: false),
          isCurrent: isActionCurrent,
        );
      } else if (action == 'resume') {
        await record.provider.updateSubscription(
          currentSub.copyWith(enabled: true),
          isCurrent: isActionCurrent,
        );
      } else if (action == 'delete') {
        await record.provider.removeSubscription(
          record.snapshot.id,
          isCurrent: isActionCurrent,
        );
      } else if (action == 'sync') {
        await record.provider.syncSubscription(
          record.snapshot.id,
          isCurrent: isActionCurrent,
        );
      }
      if (hasFeedbackAuthority()) {
        setState(() => _actionErrorState = null);
      }
    } on AccountPreferenceWriteCanceled {
      return;
    } catch (_) {
      if (hasFeedbackAuthority()) {
        final _TileActionError err;
        if (action == 'pause') {
          err = _TileActionError.pauseFailed;
        } else if (action == 'resume') {
          err = _TileActionError.resumeFailed;
        } else if (action == 'delete') {
          err = _TileActionError.deleteFailed;
        } else {
          err = _TileActionError.storageFailed;
        }
        setState(() {
          _actionErrorState = _ActionErrorState(
            error: err,
            provider: record.provider,
            origin: record.origin,
            lifetimeGeneration: record.lifetimeGeneration,
            sourceRevision: IcsSubscriptionStorage.sourceRevision(
              record.snapshot.id,
            ),
            snapshot: record.snapshot,
          );
        });
      }
    } finally {
      if (mounted && thisOp == _actionOp) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CalendarSyncProvider>();
    final sub = widget.sub;
    final isEn = NotificationUiCopy.isEn;
    final result = provider.icsRefreshResults[sub.id];

    final hasFailure =
        result != null &&
        !result.isSuccess &&
        result.status != IcsRefreshStatus.canceled;

    final actionError = _actionErrorState;
    final isActionErrorValid =
        actionError != null &&
        identical(actionError.provider, provider) &&
        actionError.origin.isCurrent(checkRoute: false) &&
        actionError.lifetimeGeneration == provider.icsLifetimeGeneration &&
        actionError.sourceRevision ==
            IcsSubscriptionStorage.sourceRevision(sub.id);
    final activeActionError = isActionErrorValid ? actionError.error : null;

    String? resultText;
    TextStyle? resultStyle;

    if (activeActionError != null) {
      switch (activeActionError) {
        case _TileActionError.pauseFailed:
          resultText = isEn
              ? 'Failed to pause subscription. Please retry.'
              : '暂停订阅失败，请重试';
          resultStyle = _icsErrorTextStyle(context);
          break;
        case _TileActionError.resumeFailed:
          resultText = isEn
              ? 'Failed to resume subscription. Please retry.'
              : '启用订阅失败，请重试';
          resultStyle = _icsErrorTextStyle(context);
          break;
        case _TileActionError.deleteFailed:
          resultText = isEn
              ? 'Failed to delete subscription. Please retry.'
              : '删除订阅失败，请重试';
          resultStyle = _icsErrorTextStyle(context);
          break;
        case _TileActionError.storageFailed:
          resultText = isEn
              ? 'Failed to update subscription. Please retry.'
              : '更新订阅失败，请重试';
          resultStyle = _icsErrorTextStyle(context);
          break;
      }
    } else if (result != null) {
      switch (result.status) {
        case IcsRefreshStatus.refreshed:
          final count = result.eventCount;
          resultText = isEn
              ? 'Refreshed ($count ${count == 1 ? "event" : "events"})'
              : '已刷新（$count 个日程）';
          resultStyle = _integrationHintTextStyle(context, fontSize: 11);
          break;
        case IcsRefreshStatus.httpFailure:
          resultText = isEn
              ? 'Network request failed. Check URL or connection.'
              : '网络请求失败，请检查链接或网络';
          resultStyle = _icsErrorTextStyle(context);
          break;
        case IcsRefreshStatus.invalidCalendar:
          resultText = isEn
              ? 'Invalid calendar format or unsupported calendar data.'
              : '日历格式无效或包含不支持的日历数据';
          resultStyle = _icsErrorTextStyle(context);
          break;
        case IcsRefreshStatus.storageFailure:
          resultText = isEn
              ? 'Failed to save calendar data locally.'
              : '本地存储写入失败，请重试';
          resultStyle = _icsErrorTextStyle(context);
          break;
        case IcsRefreshStatus.canceled:
          resultText = isEn ? 'Refresh canceled.' : '刷新已取消';
          resultStyle = _integrationHintTextStyle(context, fontSize: 11);
          break;
      }
    }

    _MenuRecordHolder holder = _activeMenuHolder ??= _MenuRecordHolder();
    if (holder.isConsumed) {
      holder = _activeMenuHolder = _MenuRecordHolder();
    }

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
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              sub.url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11),
            ),
            const SizedBox(height: 2),
            Text(
              '${sub.enabled ? (isEn ? "Active" : "已启用") : (isEn ? "Paused" : "已暂停")}'
              '${sub.lastSyncedAt == null ? "" : " · ${NotificationUiCopy.lastSyncedAt(AppDateFormat.fullDateTime(context, sub.lastSyncedAt!))}"}',
              style: _integrationHintTextStyle(context, fontSize: 11),
            ),
            if (resultText != null) ...[
              const SizedBox(height: 2),
              Text(resultText, style: resultStyle),
            ],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_busy)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (activeActionError != null)
              IconButton(
                tooltip: switch (activeActionError) {
                  _TileActionError.pauseFailed => isEn ? 'Retry pause' : '重试暂停',
                  _TileActionError.resumeFailed =>
                    isEn ? 'Retry resume' : '重试启用',
                  _TileActionError.deleteFailed =>
                    isEn ? 'Retry delete' : '重试删除',
                  _TileActionError.storageFailed =>
                    provider.icsStorageNeedsReconciliation
                        ? (isEn ? 'Recover storage' : '恢复存储')
                        : (isEn ? 'Retry update' : '重试更新'),
                },
                icon: Icon(
                  Icons.refresh,
                  size: 20,
                  color: _icsErrorTextStyle(context).color,
                ),
                onPressed: provider.isSyncing
                    ? null
                    : () => _retryFailedAction(context, provider, actionError!),
              )
            else if (hasFailure && sub.enabled)
              IconButton(
                tooltip: isEn ? 'Retry refresh' : '重试刷新',
                icon: Icon(
                  Icons.refresh,
                  size: 20,
                  color: _icsErrorTextStyle(context).color,
                ),
                onPressed: provider.isSyncing
                    ? null
                    : () => _handleDirectRetry(context, provider),
              ),
            AppLivePopupMenuButton<String>(
              enabled: !_busy && !provider.isSyncing,
              onOpened: () {
                _recordMenuOpening(context, holder, sub);
              },
              onSelected: (value) async {
                final record = holder.consume();
                if (identical(_activeMenuHolder, holder)) {
                  _activeMenuHolder = null;
                  if (mounted) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() {});
                    });
                  }
                }
                if (record != null) {
                  await _executeMenuAction(value, record);
                }
              },
              onCanceled: () {
                holder.consume();
                if (identical(_activeMenuHolder, holder)) {
                  _activeMenuHolder = null;
                  if (mounted) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() {});
                    });
                  }
                }
              },
              itemBuilder: (ctx) {
                _recordMenuOpening(context, holder, sub);
                return [
                  PopupMenuItem(
                    value: sub.enabled ? 'pause' : 'resume',
                    child: ValueListenableBuilder<AppLocale>(
                      valueListenable: I18n.localeListenable,
                      builder: (_, _, _) => AppSecondaryMenuText(
                        sub.enabled
                            ? NotificationUiCopy.menuPause
                            : NotificationUiCopy.menuResume,
                      ),
                    ),
                  ),
                  if (sub.enabled)
                    PopupMenuItem(
                      value: 'sync',
                      child: ValueListenableBuilder<AppLocale>(
                        valueListenable: I18n.localeListenable,
                        builder: (_, _, _) => AppSecondaryMenuText(
                          hasFailure
                              ? (NotificationUiCopy.isEn
                                    ? 'Retry Refresh'
                                    : '重试刷新')
                              : NotificationUiCopy.refreshAction,
                        ),
                      ),
                    ),
                  PopupMenuItem(
                    value: 'delete',
                    child: ValueListenableBuilder<AppLocale>(
                      valueListenable: I18n.localeListenable,
                      builder: (_, _, _) =>
                          AppSecondaryMenuText(NotificationUiCopy.menuDelete),
                    ),
                  ),
                ];
              },
            ),
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
              padding: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      NotificationUiCopy.locationHeaderTitle,
                      style: const TextStyle(fontWeight: FontWeight.normal),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      NotificationUiCopy.locationHeaderDescription,
                      style: _integrationHintTextStyle(context),
                    ),
                    const SizedBox(height: 12),
                    _IntegrationActionStrip(
                      children: [
                        OutlinedButton.icon(
                          onPressed: () =>
                              _testCurrentLocation(context, provider),
                          style: _integrationOutlinedButtonStyle(context),
                          icon: const Icon(Icons.my_location_outlined),
                          label: Text(
                            NotificationUiCopy.testCurrentLocationAction,
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () =>
                              _requestLocationPermissions(context, provider),
                          style: _integrationOutlinedButtonStyle(context),
                          icon: const Icon(Icons.location_searching_outlined),
                          label: Text(
                            NotificationUiCopy.grantBackgroundLocationAction,
                          ),
                        ),
                        IconButton.outlined(
                          tooltip:
                              NotificationUiCopy.systemLocationSettingsTooltip,
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
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    NotificationUiCopy.emptyLocationReminders,
                    style: _integrationHintTextStyle(context, alpha: 0.50),
                  ),
                ),
              ),
            const SizedBox(height: 80),
          ],
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: SafeArea(
            top: false,
            child: Align(
              alignment: Alignment.bottomRight,
              child: IconButton.filled(
                tooltip: NotificationUiCopy.newLocationReminderTooltip,
                onPressed: () => _addReminder(context, provider),
                icon: const Icon(Icons.add),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _addReminder(
    BuildContext context,
    LocationReminderProvider provider,
  ) async {
    final origin = SettingsActionOrigin(context);
    final initialGeneration = provider.storageGeneration;
    BuildContext? modalContext;

    bool isCurrent() {
      if (!origin.isCurrent(checkRoute: false)) return false;
      if (!context.mounted) return false;
      try {
        if (!identical(context.read<LocationReminderProvider>(), provider)) {
          return false;
        }
      } catch (_) {
        return false;
      }
      if (provider.storageGeneration != initialGeneration) return false;
      final mCtx = modalContext;
      if (mCtx == null || !mCtx.mounted) return false;
      final modalRoute = ModalRoute.of(mCtx);
      if (modalRoute == null || !modalRoute.isActive || !modalRoute.isCurrent) {
        return false;
      }
      return true;
    }

    final titleCtrl = TextEditingController();
    final latCtrl = TextEditingController();
    final lngCtrl = TextEditingController(text: '');
    final radiusCtrl = TextEditingController(text: '200');
    var trigger = LocationTrigger.enter;
    String? titleError;
    String? latError;
    String? lngError;
    String? radiusError;

    var titleInvalid = false;
    var latInvalid = false;
    var lngInvalid = false;
    var radiusInvalid = false;

    var saving = false;
    var reconciling = false;
    var hasSaveError = false;
    var hadAttempt = false;

    LocationReminder? draftSnapshot;

    await showControllerDialog<void>(
      context: context,
      controllers: [titleCtrl, latCtrl, lngCtrl, radiusCtrl],
      builder: (dialogCtx) {
        modalContext = dialogCtx;
        return ValueListenableBuilder<AppLocale>(
          valueListenable: I18n.localeListenable,
          builder: (ctx, _, _) => ListenableBuilder(
            listenable: provider,
            builder: (ctx, _) => StatefulBuilder(
              builder: (ctx, setSt) {
                modalContext = ctx;

                titleError = titleInvalid
                    ? (NotificationUiCopy.isEn
                          ? 'Please enter a reminder title'
                          : '请填写提醒标题')
                    : null;
                latError = latInvalid
                    ? (NotificationUiCopy.isEn
                          ? 'Please enter a valid latitude'
                          : '请输入有效纬度')
                    : null;
                lngError = lngInvalid
                    ? (NotificationUiCopy.isEn
                          ? 'Please enter a valid longitude'
                          : '请输入有效经度')
                    : null;
                radiusError = radiusInvalid
                    ? (NotificationUiCopy.isEn
                          ? 'Please enter a valid radius'
                          : '请输入有效半径')
                    : null;

                Future<void> doReconcile() async {
                  if (saving || reconciling) return;
                  if (!isCurrent()) return;
                  setSt(() {
                    reconciling = true;
                  });
                  try {
                    await provider.reconcileStorage();
                  } on AccountPreferenceWriteCanceled {
                    return;
                  } catch (_) {
                    // Recovery failures retain actionable UI; do not expose internals.
                  } finally {
                    if (isCurrent()) {
                      setSt(() {
                        reconciling = false;
                      });
                    }
                  }
                }

                Future<void> doSave() async {
                  if (saving || reconciling) return;
                  if (!isCurrent()) return;
                  if (provider.storageNeedsReconciliation) return;

                  final title = titleCtrl.text.trim();
                  final lat = double.tryParse(latCtrl.text.trim());
                  final lng = double.tryParse(lngCtrl.text.trim());
                  final radius = double.tryParse(radiusCtrl.text.trim());

                  final hasTitleError = title.isEmpty;
                  final hasLatError =
                      lat == null || !lat.isFinite || lat < -90.0 || lat > 90.0;
                  final hasLngError =
                      lng == null ||
                      !lng.isFinite ||
                      lng < -180.0 ||
                      lng > 180.0;
                  final hasRadiusError =
                      radius == null || !radius.isFinite || radius <= 0;

                  titleInvalid = hasTitleError;
                  latInvalid = hasLatError;
                  lngInvalid = hasLngError;
                  radiusInvalid = hasRadiusError;

                  if (hasTitleError ||
                      hasLatError ||
                      hasLngError ||
                      hasRadiusError) {
                    setSt(() {});
                    return;
                  }

                  saving = true;
                  hasSaveError = false;
                  hadAttempt = true;
                  setSt(() {});

                  if (draftSnapshot == null) {
                    draftSnapshot = LocationReminder(
                      title: title,
                      latitude: lat,
                      longitude: lng,
                      radiusMeters: radius,
                      trigger: trigger,
                    );
                  } else {
                    draftSnapshot = LocationReminder(
                      id: draftSnapshot!.id,
                      title: title,
                      latitude: lat,
                      longitude: lng,
                      radiusMeters: radius,
                      trigger: trigger,
                      createdAt: draftSnapshot!.createdAt,
                      updatedAt: draftSnapshot!.updatedAt,
                    );
                  }

                  final reminderToSave = draftSnapshot!;

                  try {
                    await provider.add(reminderToSave, isCurrent: isCurrent);
                    if (!isCurrent()) return;
                    final mCtx = modalContext;
                    if (mCtx == null || !mCtx.mounted) return;
                    Navigator.of(mCtx).pop();
                  } on AccountPreferenceWriteCanceled {
                    return;
                  } catch (_) {
                    if (!isCurrent()) return;
                    setSt(() {
                      saving = false;
                      hasSaveError = true;
                    });
                  }
                }

                final media = MediaQuery.of(ctx);
                final theme = Theme.of(ctx);
                final cs = theme.colorScheme;
                final isEn = NotificationUiCopy.isEn;
                final isRetry = hasSaveError || hadAttempt;
                final disabledActionForeground = cs.onSurface.withValues(
                  alpha: 0.38,
                );
                final textScale = media.textScaler.scale(1.0);
                final horizontalInset = media.size.width < 360 ? 12.0 : 20.0;
                final availableWidth = media.size.width - horizontalInset * 2;
                final effectiveMaxWidth = availableWidth.isFinite
                    ? availableWidth.clamp(0.0, 420.0).toDouble()
                    : 420.0;
                final dialogContentWidth = effectiveMaxWidth - 48.0;
                final isNarrowOrLargeText =
                    media.size.width < 360 || textScale > 1.15;

                final latField = TextField(
                  controller: latCtrl,
                  decoration: InputDecoration(
                    labelText: NotificationUiCopy.latitudeLabel,
                    errorText: latError,
                    errorMaxLines: 3,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: true,
                    decimal: true,
                  ),
                );

                final lngField = TextField(
                  controller: lngCtrl,
                  decoration: InputDecoration(
                    labelText: NotificationUiCopy.longitudeLabel,
                    errorText: lngError,
                    errorMaxLines: 3,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: true,
                    decimal: true,
                  ),
                );

                // Reserve the complete keyboard area for this retained form;
                // AppDialog's presentation lift alone leaves short layouts'
                // actions partially behind the keyboard.
                return Padding(
                  padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
                  child: AppDialog(
                    shiftForKeyboard: false,
                    title: Text(NotificationUiCopy.newLocationReminderTitle),
                    content: SizedBox(
                      width: dialogContentWidth,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: titleCtrl,
                            decoration: InputDecoration(
                              labelText: NotificationUiCopy.reminderTitleLabel,
                              errorText: titleError,
                              errorMaxLines: 3,
                            ),
                            autofocus: true,
                          ),
                          const SizedBox(height: 8),
                          if (isNarrowOrLargeText) ...[
                            latField,
                            const SizedBox(height: 8),
                            lngField,
                          ] else ...[
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: latField),
                                const SizedBox(width: 8),
                                Expanded(child: lngField),
                              ],
                            ),
                          ],
                          const SizedBox(height: 8),
                          TextField(
                            controller: radiusCtrl,
                            decoration: InputDecoration(
                              labelText: NotificationUiCopy.radiusMetersLabel,
                              errorText: radiusError,
                              errorMaxLines: 3,
                            ),
                            keyboardType: TextInputType.number,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            alignment: WrapAlignment.spaceBetween,
                            children: [
                              Text(NotificationUiCopy.triggerDirectionLabel),
                              Wrap(
                                spacing: 8,
                                children: [
                                  ChoiceChip(
                                    label: Text(
                                      NotificationUiCopy.triggerEnter,
                                    ),
                                    selected: trigger == LocationTrigger.enter,
                                    onSelected: saving || reconciling
                                        ? null
                                        : (_) => setSt(
                                            () =>
                                                trigger = LocationTrigger.enter,
                                          ),
                                  ),
                                  ChoiceChip(
                                    label: Text(
                                      NotificationUiCopy.triggerLeave,
                                    ),
                                    selected: trigger == LocationTrigger.leave,
                                    onSelected: saving || reconciling
                                        ? null
                                        : (_) => setSt(
                                            () =>
                                                trigger = LocationTrigger.leave,
                                          ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          if (provider.storageNeedsReconciliation) ...[
                            const SizedBox(height: 12),
                            Text(
                              NotificationUiCopy.isEn
                                  ? 'Storage state is uncertain. Please recover storage before retrying.'
                                  : '存储状态异常，重试前请先恢复存储',
                              style: TextStyle(
                                color: Theme.of(ctx).colorScheme.error,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Semantics(
                                button: true,
                                enabled: !(reconciling || saving),
                                label: reconciling
                                    ? (isEn ? 'Recovering storage…' : '正在恢复存储…')
                                    : null,
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    disabledForegroundColor:
                                        disabledActionForeground,
                                    side: BorderSide(
                                      color: (reconciling || saving)
                                          ? cs.outlineVariant.withValues(
                                              alpha: 0.16,
                                            )
                                          : cs.outlineVariant.withValues(
                                              alpha: 0.35,
                                            ),
                                      width: 0.4,
                                    ),
                                  ),
                                  onPressed: (reconciling || saving)
                                      ? null
                                      : () => doReconcile(),
                                  child: Wrap(
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    spacing: 8,
                                    runSpacing: 4,
                                    children: [
                                      if (reconciling) ...[
                                        SizedBox.square(
                                          dimension: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: cs.primary,
                                            semanticsLabel: isEn
                                                ? 'Recovering storage…'
                                                : '正在恢复存储…',
                                          ),
                                        ),
                                      ],
                                      Text(isEn ? 'Recover Storage' : '恢复存储'),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ] else if (hasSaveError) ...[
                            const SizedBox(height: 12),
                            Text(
                              isEn
                                  ? 'Failed to save reminder. Please retry.'
                                  : '保存提醒失败，请重试',
                              style: TextStyle(color: cs.error),
                            ),
                          ],
                        ],
                      ),
                    ),
                    actions: [
                      Semantics(
                        button: true,
                        enabled: !(saving || reconciling),
                        label: (saving || reconciling)
                            ? (isEn ? 'Waiting…' : '请稍候…')
                            : null,
                        child: TextButton(
                          style: TextButton.styleFrom(
                            disabledForegroundColor: disabledActionForeground,
                          ),
                          onPressed: saving || reconciling
                              ? null
                              : () {
                                  if (!isCurrent()) return;
                                  Navigator.of(modalContext!).pop();
                                },
                          child: Text(I18n.tr('action.cancel')),
                        ),
                      ),
                      Semantics(
                        button: true,
                        enabled:
                            !(saving ||
                                reconciling ||
                                provider.storageNeedsReconciliation),
                        label: saving
                            ? (isRetry
                                  ? (isEn ? 'Retrying…' : '正在重试…')
                                  : (isEn ? 'Saving…' : '正在保存…'))
                            : null,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            disabledForegroundColor: disabledActionForeground,
                          ),
                          onPressed:
                              (saving ||
                                  reconciling ||
                                  provider.storageNeedsReconciliation)
                              ? null
                              : () => doSave(),
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              if (saving) ...[
                                SizedBox.square(
                                  dimension: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: cs.primary,
                                    semanticsLabel: isRetry
                                        ? (isEn ? 'Retrying…' : '正在重试…')
                                        : (isEn ? 'Saving…' : '正在保存…'),
                                  ),
                                ),
                              ],
                              Text(
                                isRetry
                                    ? I18n.tr('action.retry')
                                    : I18n.tr('action.save'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
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
    final media = MediaQuery.maybeOf(context);
    final isNarrowHighText =
        permission.shouldOpenSettings &&
        media != null &&
        media.size.width < 360 &&
        media.textScaler.scale(14) >= 21;
    final feedbackText = _RetainedFeedbackText(
      () => sync == null
          ? NotificationUiCopy.formatLocationPermissionMessage(
              permission.message,
            )
          : NotificationUiCopy.locationSynced(sync.scheduledCount),
    );
    final settingsAction = permission.shouldOpenSettings
        ? _RetainedLocaleSnackBarAction(
            labelBuilder: () => NotificationUiCopy.toSettingsAction,
            onPressed: LocationGeofenceService.openLocationSettings,
          )
        : null;
    ScaffoldMessenger.of(context).showSnackBar(
      isNarrowHighText
          ? SnackBar(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  feedbackText,
                  const SizedBox(height: 6),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: settingsAction!,
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              behavior: SnackBarBehavior.floating,
              persist: true,
            )
          : SnackBar(
              content: feedbackText,
              behavior: SnackBarBehavior.floating,
              action: settingsAction,
            ),
    );
  }

  Future<void> _testCurrentLocation(
    BuildContext context,
    LocationReminderProvider provider,
  ) async {
    final origin = SettingsActionOrigin(context);
    final generation = provider.storageGeneration;
    bool isCurrent() =>
        origin.isCurrent() &&
        provider.storageGeneration == generation &&
        identical(context.read<LocationReminderProvider>(), provider);
    final latCtrl = TextEditingController();
    final lngCtrl = TextEditingController();
    final ok = await showControllerDialog<bool>(
      context: context,
      controllers: [latCtrl, lngCtrl],
      builder: (ctx) => ValueListenableBuilder<AppLocale>(
        valueListenable: I18n.localeListenable,
        builder: (ctx, _, _) => AppDialog(
          title: Text(NotificationUiCopy.testInputLocationTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: latCtrl,
                      decoration: InputDecoration(
                        labelText: NotificationUiCopy.latitudeLabel,
                      ),
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
                      decoration: InputDecoration(
                        labelText: NotificationUiCopy.longitudeLabel,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: true,
                        decimal: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                NotificationUiCopy.testInputLocationDescription,
                style: _integrationHintTextStyle(context),
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
              child: Text(NotificationUiCopy.testButton),
            ),
          ],
        ),
      ),
    );
    final lat = double.tryParse(latCtrl.text.trim());
    final lng = double.tryParse(lngCtrl.text.trim());
    if (ok != true || !context.mounted) return;

    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: _RetainedFeedbackText(
            () => NotificationUiCopy.validCoordinatesRequired,
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (!isCurrent()) return;
    final hits = await provider.ingestFix(
      LocationFix(latitude: lat, longitude: lng, at: DateTime.now()),
      isCurrent: isCurrent,
    );
    if (!isCurrent()) return;
    if (!context.mounted) return;
    final notificationService = context.read<NotificationService>();
    for (final hit in hits) {
      notificationService.notifyLocationReminderHit(hit);
    }

    if (!context.mounted) return;
    final hitCount = hits.length;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: _RetainedFeedbackText(
          () => hitCount == 0
              ? NotificationUiCopy.locationNoHits
              : NotificationUiCopy.locationTriggeredHits(hitCount),
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
          '${NotificationUiCopy.locationTriggerSuffix(reminder.trigger == LocationTrigger.enter)}',
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

  Future<void> _selectLocale(
    BuildContext context,
    LocaleProvider provider,
    AppLocale selection,
  ) async {
    try {
      await provider.setLocale(selection);
    } catch (_) {
      if (!context.mounted) return;
      var executed = false;
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          persist: true,
          content: ValueListenableBuilder<AppLocale>(
            valueListenable: I18n.localeListenable,
            builder: (contentContext, _, _) {
              final theme = Theme.of(contentContext);
              final cs = theme.colorScheme;
              final snackBarBackground =
                  theme.snackBarTheme.backgroundColor ??
                  cs.surfaceContainerHighest;
              final renderedFill = Color.alphaBlend(
                snackBarBackground,
                Colors.white,
              );
              final foreground = appReadableForeground(
                renderedFill,
                theme.snackBarTheme.actionTextColor ?? cs.primary,
              );
              return Row(
                children: [
                  Expanded(child: Text(NotificationUiCopy.localeSaveFailed)),
                  const SizedBox(width: 8),
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: foreground,
                      minimumSize: const Size(48, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () {
                      if (executed) return;
                      executed = true;
                      messenger.hideCurrentSnackBar(
                        reason: SnackBarClosedReason.action,
                      );
                      _selectLocale(context, provider, selection);
                    },
                    child: Text(I18n.tr('action.retry')),
                  ),
                ],
              );
            },
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleProvider>();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          I18n.tr('settings.language'),
          style: const TextStyle(fontWeight: FontWeight.normal),
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
            onTap: () => _selectLocale(context, locale, entry.$1),
          ),
        const SizedBox(height: 16),
        Text(
          I18n.tr('settings.language.description'),
          style: _integrationHintTextStyle(context),
        ),
      ],
    );
  }
}

class _RetainedFeedbackText extends StatelessWidget {
  const _RetainedFeedbackText(this.message);

  final String Function() message;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, _, _) => Text(message()),
    );
  }
}

/// Preserves [SnackBar.action] non-null persistence and [onPressed] identity
/// while rebuilding the rendered [SnackBarAction] label on locale changes.
class _RetainedLocaleSnackBarAction extends SnackBarAction {
  const _RetainedLocaleSnackBarAction({
    required this.labelBuilder,
    required super.onPressed,
  }) : super(label: '');

  final String Function() labelBuilder;

  @override
  String get label => labelBuilder();

  @override
  State<SnackBarAction> createState() => _RetainedLocaleSnackBarActionState();
}

class _RetainedLocaleSnackBarActionState extends State<SnackBarAction> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, _, _) => SnackBarAction(
        textColor: widget.textColor,
        disabledTextColor: widget.disabledTextColor,
        backgroundColor: widget.backgroundColor,
        disabledBackgroundColor: widget.disabledBackgroundColor,
        label: widget.label,
        onPressed: widget.onPressed,
      ),
    );
  }
}
