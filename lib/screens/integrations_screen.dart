/// 扩展功能：日历订阅 + 位置提醒 + 语言设置（Task T-* 集成 UI）。
///
/// 把 v2 阶段新增的三类"边缘能力"集中在一个 Tab 化页面里：
/// - 日历订阅：用户粘贴 .ics URL 即可让多仪日历显示外部日程；
/// - 位置提醒：手动录入坐标 + 半径 + 触发方向；
/// - 语言：在中 / 英 之间切换。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/i18n.dart';
import '../core/i18n_date_format.dart';
import '../core/notification_ui_copy.dart';
import '../models/location_reminder.dart';
import '../providers/location_reminder_provider.dart';
import '../providers/notification_service.dart';
import '../services/calendar_sync_service.dart';
import '../services/location_geofence_service.dart';
import '../widgets/surface_components.dart';
import '../widgets/controller_dialog.dart';

class IntegrationsScreen extends StatelessWidget {
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
        return DefaultTabController(
          length: 3,
          child: Scaffold(
            backgroundColor: routeBackground,
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
                  const _LocationRemindersTab(),
                  const _LocaleTab(),
                ],
              ),
            ),
          ),
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
                      onPressed: provider.isSyncing
                          ? null
                          // ignore: discarded_futures
                          : () => provider.syncAll(),
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
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    String? nameError;
    String? urlError;
    final ok = await showControllerDialog<bool>(
      context: context,
      controllers: [nameCtrl, urlCtrl],
      builder: (ctx) => ValueListenableBuilder<AppLocale>(
        valueListenable: I18n.localeListenable,
        builder: (ctx, _, _) => StatefulBuilder(
          builder: (ctx, setState) => AppDialog(
            title: Text(NotificationUiCopy.addSubscriptionDialogTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: NotificationUiCopy.subscriptionNameLabel,
                    errorText: nameError,
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
                  ),
                  keyboardType: TextInputType.url,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(I18n.tr('action.cancel')),
              ),
              FilledButton(
                onPressed: () {
                  final name = nameCtrl.text.trim();
                  final url = urlCtrl.text.trim();
                  final uri = Uri.tryParse(url);
                  final validUrl =
                      uri != null &&
                      uri.host.isNotEmpty &&
                      (uri.scheme == 'http' || uri.scheme == 'https');
                  setState(() {
                    nameError = name.isEmpty
                        ? (NotificationUiCopy.isEn
                              ? 'Please enter a subscription name'
                              : '请填写订阅名称')
                        : null;
                    urlError = url.isEmpty
                        ? (NotificationUiCopy.isEn
                              ? 'Please enter an ICS URL'
                              : '请填写 ICS URL')
                        : (!validUrl
                              ? (NotificationUiCopy.isEn
                                    ? 'Please enter a valid http/https address'
                                    : '请输入有效的 http/https 地址')
                              : null);
                  });
                  if (nameError == null && urlError == null) {
                    Navigator.pop(ctx, true);
                  }
                },
                child: Text(I18n.tr('action.add')),
              ),
            ],
          ),
        ),
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
            SnackBar(content: Text(NotificationUiCopy.oauthStateMismatch)),
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
      builder: (ctx) => ValueListenableBuilder<AppLocale>(
        valueListenable: I18n.localeListenable,
        builder: (ctx, _, _) => StatefulBuilder(
          builder: (dialogContext, setState) {
            final authUri = buildAuthUri();
            return AppDialog(
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
                                                content: Text(
                                                  NotificationUiCopy
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
                                                  content: Text(
                                                    NotificationUiCopy
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
            );
          },
        ),
      ),
    );

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
        SnackBar(content: Text(NotificationUiCopy.oauthFieldsRequired)),
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
        SnackBar(content: Text(NotificationUiCopy.oauthConnected)),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(NotificationUiCopy.formatOauthConnectError(e))),
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
          '${account.lastSyncedAt == null ? "" : " · ${NotificationUiCopy.lastSyncedAt(_formatDateTime(account.lastSyncedAt!))}"}',
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
              child: AppSecondaryMenuText(
                account.enabled
                    ? (NotificationUiCopy.isEn ? 'Pause' : '暂停')
                    : (NotificationUiCopy.isEn ? 'Resume' : '启用'),
              ),
            ),
            PopupMenuItem(
              value: 'sync',
              child: AppSecondaryMenuText(NotificationUiCopy.menuSync),
            ),
            PopupMenuItem(
              value: 'delete',
              child: AppSecondaryMenuText(NotificationUiCopy.menuDelete),
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

  @override
  Widget build(BuildContext context) {
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
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: _integrationHintTextStyle(context),
            ),
            if (provider.lastCalDavConflicts.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                NotificationUiCopy.calDavConflictsSkipped(
                  provider.lastCalDavConflicts.length,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: _integrationWarningTextStyle(context),
              ),
            ],
            if (target?.lastTestedAt != null) ...[
              const SizedBox(height: 4),
              Text(
                NotificationUiCopy.lastTestedAt(
                  _formatDateTime(target!.lastTestedAt!),
                ),
                style: _integrationHintTextStyle(
                  context,
                  fontSize: 11,
                  alpha: 0.50,
                ),
              ),
            ],
            if (provider.lastError != null) ...[
              const SizedBox(height: 6),
              Text(
                NotificationUiCopy.formatCalDavError(provider.lastError!),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: _integrationErrorTextStyle(context),
              ),
            ],
            const SizedBox(height: 10),
            _IntegrationActionStrip(
              children: [
                OutlinedButton.icon(
                  onPressed: () => _showCalDavDialog(context, provider),
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
                        : provider.clearWriteTarget,
                    style: _integrationOutlinedButtonStyle(context),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: Text(NotificationUiCopy.calDavRemove),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _showICloudCalDavDialog(context, provider),
                  style: _integrationOutlinedButtonStyle(context),
                  icon: const Icon(Icons.apple, size: 16),
                  label: const Text('iCloud'),
                ),
                FilledButton.tonalIcon(
                  onPressed: !configured || provider.isTestingWriteTarget
                      ? null
                      : provider.testWriteTarget,
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
      CalDavConflictPolicy.skipRemoteChanges =>
        NotificationUiCopy.isEn ? 'Keep remote changes' : '远端变更不覆盖',
      CalDavConflictPolicy.overwriteRemote =>
        NotificationUiCopy.isEn ? 'Overwrite remote' : '覆盖远端',
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
              child: AppSecondaryMenuText(
                sub.enabled
                    ? (NotificationUiCopy.isEn ? 'Pause' : '暂停')
                    : (NotificationUiCopy.isEn ? 'Resume' : '启用'),
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              child: AppSecondaryMenuText(NotificationUiCopy.menuDelete),
            ),
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
    final titleCtrl = TextEditingController();
    final latCtrl = TextEditingController();
    final lngCtrl = TextEditingController(text: '');
    final radiusCtrl = TextEditingController(text: '200');
    var trigger = LocationTrigger.enter;
    String? titleError;
    String? latError;
    String? lngError;
    String? radiusError;
    final ok = await showControllerDialog<bool>(
      context: context,
      controllers: [titleCtrl, latCtrl, lngCtrl, radiusCtrl],
      builder: (ctx) => ValueListenableBuilder<AppLocale>(
        valueListenable: I18n.localeListenable,
        builder: (ctx, _, _) => StatefulBuilder(
          builder: (ctx, setSt) => AppDialog(
            title: Text(NotificationUiCopy.newLocationReminderTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: InputDecoration(
                    labelText: NotificationUiCopy.reminderTitleLabel,
                    errorText: titleError,
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: latCtrl,
                        decoration: InputDecoration(
                          labelText: NotificationUiCopy.latitudeLabel,
                          errorText: latError,
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
                          errorText: lngError,
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
                TextField(
                  controller: radiusCtrl,
                  decoration: InputDecoration(
                    labelText: NotificationUiCopy.radiusMetersLabel,
                    errorText: radiusError,
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(NotificationUiCopy.triggerDirectionLabel),
                    const Spacer(),
                    ChoiceChip(
                      label: Text(NotificationUiCopy.triggerEnter),
                      selected: trigger == LocationTrigger.enter,
                      onSelected: (_) =>
                          setSt(() => trigger = LocationTrigger.enter),
                    ),
                    const SizedBox(width: 4),
                    ChoiceChip(
                      label: Text(NotificationUiCopy.triggerLeave),
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
                onPressed: () {
                  final title = titleCtrl.text.trim();
                  final lat = double.tryParse(latCtrl.text.trim());
                  final lng = double.tryParse(lngCtrl.text.trim());
                  final radius = double.tryParse(radiusCtrl.text.trim());
                  setSt(() {
                    titleError = title.isEmpty
                        ? (NotificationUiCopy.isEn
                              ? 'Please enter a reminder title'
                              : '请填写提醒标题')
                        : null;
                    latError = lat == null
                        ? (NotificationUiCopy.isEn
                              ? 'Please enter a valid latitude'
                              : '请输入有效纬度')
                        : null;
                    lngError = lng == null
                        ? (NotificationUiCopy.isEn
                              ? 'Please enter a valid longitude'
                              : '请输入有效经度')
                        : null;
                    radiusError = radius == null || radius <= 0
                        ? (NotificationUiCopy.isEn
                              ? 'Please enter a valid radius'
                              : '请输入有效半径')
                        : null;
                  });
                  if (titleError == null &&
                      latError == null &&
                      lngError == null &&
                      radiusError == null) {
                    Navigator.pop(ctx, true);
                  }
                },
                child: Text(I18n.tr('action.save')),
              ),
            ],
          ),
        ),
      ),
    );
    final title = titleCtrl.text.trim();
    final lat = double.tryParse(latCtrl.text.trim());
    final lng = double.tryParse(lngCtrl.text.trim());
    final radius = double.tryParse(radiusCtrl.text.trim()) ?? 200;
    if (ok != true) return;
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
              ? NotificationUiCopy.formatLocationPermissionMessage(
                  permission.message,
                )
              : NotificationUiCopy.locationSynced(sync.scheduledCount),
        ),
        behavior: SnackBarBehavior.floating,
        action: permission.shouldOpenSettings
            ? SnackBarAction(
                label: NotificationUiCopy.toSettingsAction,
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
          content: Text(NotificationUiCopy.validCoordinatesRequired),
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
          hits.isEmpty
              ? NotificationUiCopy.locationNoHits
              : NotificationUiCopy.locationTriggeredHits(hits.length),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(NotificationUiCopy.localeSaveFailed),
          action: SnackBarAction(
            label: I18n.tr('action.retry'),
            onPressed: () => _selectLocale(context, provider, selection),
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
