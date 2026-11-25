import '../widgets/app_date_format.dart';
import 'dart:async';
import 'dart:io' show File;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../core/admin_announcement_ui_copy.dart';
import '../core/admin_audit_ui_copy.dart';
import '../core/admin_feedback_ui_copy.dart';
import '../core/admin_invite_ui_copy.dart';
import '../core/admin_ui_copy.dart';
import '../core/app_version.dart';
import '../core/app_config.dart';
import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../core/i18n_date_format.dart';
import '../providers/auth_provider.dart';
import '../providers/app_lock_provider.dart';
import '../services/admin_api.dart';
import '../services/admin_action_origin.dart';
import '../services/admin_feedback_export.dart';
import '../services/app_access_route_gate.dart';
import '../services/app_update_service.dart';
import '../services/ai_service.dart';
import '../services/api_client.dart';
import '../widgets/empty_state.dart';
import '../widgets/surface_components.dart';
import '../widgets/brand_background.dart'
    show BrandBackground, BrandRouteSurface, LocaleStatePreservingRoute;

/// 管理员后台 — 仅当 AuthProvider.state.isAdmin == true 时可进入。
class AdminScreen extends StatefulWidget implements LocaleStatePreservingRoute {
  final int initialTabIndex;
  final AdminFeedbackExportEffects feedbackExportEffects;

  const AdminScreen({
    super.key,
    this.initialTabIndex = 0,
    this.feedbackExportEffects = const PlatformAdminFeedbackExportEffects(),
  });

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen>
    with SingleTickerProviderStateMixin {
  static const int _adminTabCount = 10;
  late TabController _tabs;
  late final List<int> _tabRefreshSerials;
  late int _activeTabIndex;
  final _announcementsViewRevision = ValueNotifier<int>(0);
  final _invitesViewRevision = ValueNotifier<int>(0);
  final _usersViewRevision = ValueNotifier<int>(0);
  final _auditViewRevision = ValueNotifier<int>(0);
  final _feedbackViewRevision = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _activeTabIndex = widget.initialTabIndex.clamp(0, _adminTabCount - 1);
    _tabs = TabController(
      length: _adminTabCount,
      vsync: this,
      initialIndex: _activeTabIndex,
    );
    _tabs.addListener(_handleTabChanged);
    _tabRefreshSerials = List<int>.filled(_adminTabCount, 0);
    I18n.localeListenable.addListener(_handleLocaleChanged);
  }

  @override
  void dispose() {
    I18n.localeListenable.removeListener(_handleLocaleChanged);
    _tabs.removeListener(_handleTabChanged);
    _tabs.dispose();
    _announcementsViewRevision.dispose();
    _invitesViewRevision.dispose();
    _usersViewRevision.dispose();
    _auditViewRevision.dispose();
    _feedbackViewRevision.dispose();
    super.dispose();
  }

  void _handleLocaleChanged() {
    if (mounted) setState(() {});
  }

  void _handleTabChanged() {
    final nextIndex = _tabs.index.clamp(0, _adminTabCount - 1);
    if (nextIndex == _activeTabIndex) return;
    if (_activeTabIndex == 6 || nextIndex == 6) {
      _announcementsViewRevision.value++;
    }
    if (_activeTabIndex == 8 || nextIndex == 8) {
      _invitesViewRevision.value++;
    }
    if (_activeTabIndex == 4 || nextIndex == 4) {
      _usersViewRevision.value++;
    }
    if (_activeTabIndex == 7 || nextIndex == 7) {
      _feedbackViewRevision.value++;
    }
    if (_activeTabIndex == 9 || nextIndex == 9) {
      _auditViewRevision.value++;
    }
    setState(() => _activeTabIndex = nextIndex);
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    final baseTheme = Theme.of(context);
    final theme = isMobile ? _buildAdminMobileTheme(baseTheme) : baseTheme;
    final auth = context.watch<AuthProvider>();
    final cs = theme.colorScheme;
    final routeBackground = theme.brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;
    final surfaceStyle = appSurfaceStyleOf(context);
    final isLiquidGlass = surfaceStyle == AppSurfaceStyle.liquidGlass;

    Widget wrapWithSurface(Widget scaffold) {
      final themed = Theme(data: theme, child: scaffold);
      if (!isLiquidGlass) {
        return themed;
      }
      final hasBrandSurface =
          context.findAncestorWidgetOfExactType<BrandBackground>() != null ||
          context.findAncestorWidgetOfExactType<BrandRouteSurface>() != null;
      if (hasBrandSurface) {
        return themed;
      }
      return Material(
        color: routeBackground,
        child: BrandBackground(child: themed),
      );
    }

    if (!auth.state.isAdmin) {
      return wrapWithSurface(
        Scaffold(
          backgroundColor: isLiquidGlass ? Colors.transparent : routeBackground,
          appBar: AppBar(
            title: Text(AdminUiCopy.adminScreenTitle),
            titleTextStyle: appSecondaryRouteTitleTextStyle(context),
            backgroundColor: routeBackground.withValues(alpha: 0.96),
            surfaceTintColor: Colors.transparent,
          ),
          body: EmptyState(
            icon: Icons.lock,
            message: AdminUiCopy.adminAccessOnly,
          ),
        ),
      );
    }
    final api = AdminApi(auth.client);
    final permissions = auth.state.adminPermissions?.toSet().toList();
    permissions?.sort();
    final accessKey = (auth.state.userId, permissions?.join(',') ?? 'legacy');
    bool canAccess(String permission) =>
        permissions == null ||
        (!permissions.contains(_adminNoPermission) &&
            (permissions.contains(_adminAllPermission) ||
                permissions.contains(permission)));

    return wrapWithSurface(
      Scaffold(
        backgroundColor: isLiquidGlass ? Colors.transparent : routeBackground,
        appBar: AppBar(
          title: Text(AdminUiCopy.adminScreenTitle),
          titleTextStyle: appSecondaryRouteTitleTextStyle(context),
          backgroundColor: routeBackground.withValues(alpha: 0.96),
          surfaceTintColor: Colors.transparent,
          actions: [
            PopupMenuButton<int>(
              tooltip: AdminUiCopy.selectModuleTooltip,
              icon: const Icon(Icons.grid_view_outlined),
              initialValue: _activeTabIndex,
              onSelected: (index) {
                if (index != _tabs.index) {
                  _tabs.animateTo(index);
                }
              },
              itemBuilder: (context) {
                final tabsMeta = AdminUiCopy.moduleTabsMeta;
                return [
                  for (var i = 0; i < tabsMeta.length; i++)
                    PopupMenuItem<int>(
                      value: i,
                      height: 48,
                      child: Row(
                        children: [
                          Icon(
                            tabsMeta[i].$1,
                            size: 18,
                            color: _activeTabIndex == i
                                ? cs.primary
                                : cs.onSurfaceVariant,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ValueListenableBuilder<AppLocale>(
                              valueListenable: I18n.localeListenable,
                              builder: (context, locale, _) {
                                return Text(
                                  AdminUiCopy.tabTitleForIndex(i, locale),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: _activeTabIndex == i
                                        ? cs.primary
                                        : cs.onSurface,
                                  ),
                                );
                              },
                            ),
                          ),
                          if (_activeTabIndex == i)
                            Icon(Icons.check, size: 16, color: cs.primary),
                        ],
                      ),
                    ),
                ];
              },
            ),
            IconButton(
              tooltip: AdminUiCopy.refreshCurrentPageTooltip,
              onPressed: () {
                final index = _tabs.index.clamp(
                  0,
                  _tabRefreshSerials.length - 1,
                );
                setState(() => _tabRefreshSerials[index]++);
              },
              icon: const Icon(Icons.refresh),
            ),
          ],
          bottom: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            labelPadding: const EdgeInsets.symmetric(horizontal: 6),
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: Colors.transparent,
            labelStyle: appSecondaryMenuItemTextStyle(context),
            unselectedLabelStyle: appSecondaryMenuItemTextStyle(context),
            indicator: BoxDecoration(
              color: Color.alphaBlend(
                cs.primary.withValues(alpha: 0.10),
                cs.surface,
              ),
              borderRadius: BorderRadius.circular(DesignTokens.radiusControl),
              border: Border.all(
                color: cs.primary.withValues(alpha: 0.20),
                width: 0.45,
              ),
            ),
            labelColor: cs.onSurface,
            unselectedLabelColor: cs.onSurfaceVariant,
            tabs: const [
              Tab(
                height: 36,
                child: _AdminTabLabel(
                  icon: Icons.dashboard_outlined,
                  text: '概览',
                ),
              ),
              Tab(
                height: 36,
                child: _AdminTabLabel(icon: Icons.tune, text: '全站设置'),
              ),
              Tab(
                height: 36,
                child: _AdminTabLabel(icon: Icons.auto_awesome, text: 'AI 配置'),
              ),
              Tab(
                height: 36,
                child: _AdminTabLabel(icon: Icons.cloud_outlined, text: '云端备份'),
              ),
              Tab(
                height: 36,
                child: _AdminTabLabel(icon: Icons.people_outline, text: '用户'),
              ),
              Tab(
                height: 36,
                child: _AdminTabLabel(
                  icon: Icons.groups_2_outlined,
                  text: '用户组',
                ),
              ),
              Tab(
                height: 36,
                child: _AdminTabLabel(
                  icon: Icons.campaign_outlined,
                  text: '公告',
                ),
              ),
              Tab(
                height: 36,
                child: _AdminTabLabel(
                  icon: Icons.feedback_outlined,
                  text: '许愿与反馈',
                ),
              ),
              Tab(
                height: 36,
                child: _AdminTabLabel(
                  icon: Icons.vpn_key_outlined,
                  text: '邀请码',
                ),
              ),
              Tab(
                height: 36,
                child: _AdminTabLabel(
                  icon: Icons.receipt_long_outlined,
                  text: '日志',
                ),
              ),
            ],
          ),
        ),
        body: TabBarView(
          key: ValueKey(accessKey),
          controller: _tabs,
          children: [
            _AdminTabContent(
              child: _DashboardTab(
                key: ValueKey('admin-dashboard-${_tabRefreshSerials[0]}'),
                api: api,
              ),
            ),
            _AdminTabContent(
              allowed: canAccess('settings'),
              child: _SettingsTab(
                key: ValueKey('admin-settings-${_tabRefreshSerials[1]}'),
                api: api,
                selfAdminPermissions: auth.state.adminPermissions,
              ),
            ),
            _AdminTabContent(
              allowed: canAccess('ai'),
              child: _AiSettingsTab(
                key: ValueKey('admin-ai-${_tabRefreshSerials[2]}'),
                api: api,
              ),
            ),
            _AdminTabContent(
              allowed: canAccess('backup'),
              child: _BackupSettingsTab(
                key: ValueKey('admin-backup-${_tabRefreshSerials[3]}'),
                api: api,
              ),
            ),
            _AdminTabContent(
              allowed: const [
                'users',
                'coins',
                'groups',
                'roles',
                'permissions',
              ].any(canAccess),
              child: _UsersTab(
                key: ValueKey('admin-users-${_tabRefreshSerials[4]}'),
                api: api,
                selfId: auth.state.userId,
                selfAdminPermissions: auth.state.adminPermissions,
                isActive: _activeTabIndex == 4,
                activationRevision: _usersViewRevision,
              ),
            ),
            _AdminTabContent(
              child: _GroupsTab(
                key: ValueKey('admin-groups-${_tabRefreshSerials[5]}'),
                api: api,
                selfAdminPermissions: auth.state.adminPermissions,
              ),
            ),
            _AdminTabContent(
              allowed: canAccess('announcements'),
              child: _AnnouncementsTab(
                key: ValueKey('admin-announcements-${_tabRefreshSerials[6]}'),
                api: api,
                isActive: _activeTabIndex == 6,
                activationRevision: _announcementsViewRevision,
              ),
            ),
            _AdminTabContent(
              allowed: canAccess('feedback'),
              child: _FeedbackTab(
                key: ValueKey('admin-feedback-${_tabRefreshSerials[7]}'),
                api: api,
                exportEffects: widget.feedbackExportEffects,
                isActiveNow: () => _tabs.index == 7,
                activationRevision: _feedbackViewRevision,
              ),
            ),
            _AdminTabContent(
              allowed: canAccess('invites'),
              child: _InvitesTab(
                key: ValueKey('admin-invites-${_tabRefreshSerials[8]}'),
                api: api,
                isActive: _activeTabIndex == 8,
                activationRevision: _invitesViewRevision,
              ),
            ),
            _AdminTabContent(
              allowed: canAccess('audit'),
              child: _AuditLogTab(
                key: ValueKey('admin-audit-${_tabRefreshSerials[9]}'),
                api: api,
                isActiveNow: () => _tabs.index == 9,
                activationRevision: _auditViewRevision,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

ThemeData _buildAdminMobileTheme(ThemeData baseTheme) {
  final baseText = baseTheme.textTheme;

  final mobileTextTheme = baseText.copyWith(
    // Page title: restrained 16-18
    titleLarge: (baseText.titleLarge ?? const TextStyle()).copyWith(
      fontSize: 17,
      fontWeight: FontWeight.normal,
    ),
    // Standard titleMedium: 14 normal400
    titleMedium: (baseText.titleMedium ?? const TextStyle()).copyWith(
      fontSize: 14,
      fontWeight: FontWeight.normal,
    ),
    // Section title: 14-15
    titleSmall: (baseText.titleSmall ?? const TextStyle()).copyWith(
      fontSize: 14.5,
      fontWeight: FontWeight.normal,
    ),
    // Body: 13-14
    bodyLarge: (baseText.bodyLarge ?? const TextStyle()).copyWith(
      fontSize: 14,
      fontWeight: FontWeight.normal,
    ),
    bodyMedium: (baseText.bodyMedium ?? const TextStyle()).copyWith(
      fontSize: 13.5,
      fontWeight: FontWeight.normal,
    ),
    // Supporting: 12-13
    bodySmall: (baseText.bodySmall ?? const TextStyle()).copyWith(
      fontSize: 12.5,
      fontWeight: FontWeight.normal,
    ),
    // Form labels / Buttons / Chips
    labelLarge: (baseText.labelLarge ?? const TextStyle()).copyWith(
      fontSize: 13.5,
      fontWeight: FontWeight.normal,
    ),
    labelMedium: (baseText.labelMedium ?? const TextStyle()).copyWith(
      fontSize: 12,
      fontWeight: FontWeight.normal,
    ),
    labelSmall: (baseText.labelSmall ?? const TextStyle()).copyWith(
      fontSize: 12,
      fontWeight: FontWeight.normal,
    ),
    headlineSmall: (baseText.headlineSmall ?? const TextStyle()).copyWith(
      fontSize: 17,
      fontWeight: FontWeight.normal,
    ),
    headlineMedium: (baseText.headlineMedium ?? const TextStyle()).copyWith(
      fontSize: 17,
      fontWeight: FontWeight.normal,
    ),
  );

  return baseTheme.copyWith(
    textTheme: mobileTextTheme,
    listTileTheme: baseTheme.listTileTheme.copyWith(
      titleTextStyle:
          (baseTheme.listTileTheme.titleTextStyle ??
                  mobileTextTheme.titleSmall ??
                  const TextStyle())
              .copyWith(fontSize: 14, fontWeight: FontWeight.normal),
      subtitleTextStyle:
          (baseTheme.listTileTheme.subtitleTextStyle ??
                  mobileTextTheme.bodySmall ??
                  const TextStyle())
              .copyWith(fontSize: 12.5, fontWeight: FontWeight.normal),
      leadingAndTrailingTextStyle:
          (baseTheme.listTileTheme.leadingAndTrailingTextStyle ??
                  mobileTextTheme.labelSmall ??
                  const TextStyle())
              .copyWith(fontSize: 12, fontWeight: FontWeight.normal),
    ),
    dataTableTheme: baseTheme.dataTableTheme.copyWith(
      headingTextStyle:
          (baseTheme.dataTableTheme.headingTextStyle ??
                  mobileTextTheme.titleSmall ??
                  const TextStyle())
              .copyWith(fontSize: 13, fontWeight: FontWeight.normal),
      dataTextStyle:
          (baseTheme.dataTableTheme.dataTextStyle ??
                  mobileTextTheme.bodyMedium ??
                  const TextStyle())
              .copyWith(fontSize: 13, fontWeight: FontWeight.normal),
    ),
    inputDecorationTheme: baseTheme.inputDecorationTheme.copyWith(
      helperMaxLines: 5,
      errorMaxLines: 3,
      labelStyle:
          (baseTheme.inputDecorationTheme.labelStyle ??
                  mobileTextTheme.bodyMedium ??
                  const TextStyle())
              .copyWith(fontSize: 13.5, fontWeight: FontWeight.normal),
      floatingLabelStyle:
          (baseTheme.inputDecorationTheme.floatingLabelStyle ??
                  mobileTextTheme.bodySmall ??
                  const TextStyle())
              .copyWith(fontSize: 12.5, fontWeight: FontWeight.normal),
      hintStyle:
          (baseTheme.inputDecorationTheme.hintStyle ??
                  mobileTextTheme.bodyMedium ??
                  const TextStyle())
              .copyWith(fontSize: 13.5, fontWeight: FontWeight.normal),
      helperStyle:
          (baseTheme.inputDecorationTheme.helperStyle ??
                  mobileTextTheme.bodySmall ??
                  const TextStyle())
              .copyWith(fontSize: 12, fontWeight: FontWeight.normal),
      errorStyle:
          (baseTheme.inputDecorationTheme.errorStyle ??
                  mobileTextTheme.bodySmall ??
                  const TextStyle())
              .copyWith(fontSize: 12, fontWeight: FontWeight.normal),
      prefixStyle:
          (baseTheme.inputDecorationTheme.prefixStyle ??
                  mobileTextTheme.bodyMedium ??
                  const TextStyle())
              .copyWith(fontSize: 13, fontWeight: FontWeight.normal),
      suffixStyle:
          (baseTheme.inputDecorationTheme.suffixStyle ??
                  mobileTextTheme.bodyMedium ??
                  const TextStyle())
              .copyWith(fontSize: 13, fontWeight: FontWeight.normal),
    ),
    dialogTheme: baseTheme.dialogTheme.copyWith(
      titleTextStyle:
          (baseTheme.dialogTheme.titleTextStyle ??
                  mobileTextTheme.titleLarge ??
                  const TextStyle())
              .copyWith(fontSize: 16, fontWeight: FontWeight.normal),
      contentTextStyle:
          (baseTheme.dialogTheme.contentTextStyle ??
                  mobileTextTheme.bodyMedium ??
                  const TextStyle())
              .copyWith(fontSize: 13.5, fontWeight: FontWeight.normal),
    ),
    appBarTheme: baseTheme.appBarTheme.copyWith(
      titleTextStyle:
          (baseTheme.appBarTheme.titleTextStyle ??
                  mobileTextTheme.titleLarge ??
                  const TextStyle())
              .copyWith(fontSize: 17, fontWeight: FontWeight.normal),
    ),
    tabBarTheme: baseTheme.tabBarTheme.copyWith(
      labelStyle:
          (baseTheme.tabBarTheme.labelStyle ??
                  mobileTextTheme.titleSmall ??
                  const TextStyle())
              .copyWith(fontSize: 13, fontWeight: FontWeight.normal),
      unselectedLabelStyle:
          (baseTheme.tabBarTheme.unselectedLabelStyle ??
                  mobileTextTheme.titleSmall ??
                  const TextStyle())
              .copyWith(fontSize: 13, fontWeight: FontWeight.normal),
    ),
    chipTheme: baseTheme.chipTheme.copyWith(
      labelStyle:
          (baseTheme.chipTheme.labelStyle ??
                  mobileTextTheme.labelMedium ??
                  const TextStyle())
              .copyWith(fontSize: 12, fontWeight: FontWeight.normal),
    ),
    textButtonTheme: TextButtonThemeData(
      style: (baseTheme.textButtonTheme.style ?? const ButtonStyle()).copyWith(
        textStyle: WidgetStatePropertyAll(
          (mobileTextTheme.labelLarge ?? const TextStyle()).copyWith(
            fontSize: 13.5,
            fontWeight: FontWeight.normal,
          ),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: (baseTheme.outlinedButtonTheme.style ?? const ButtonStyle())
          .copyWith(
            textStyle: WidgetStatePropertyAll(
              (mobileTextTheme.labelLarge ?? const TextStyle()).copyWith(
                fontSize: 13.5,
                fontWeight: FontWeight.normal,
              ),
            ),
          ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: (baseTheme.filledButtonTheme.style ?? const ButtonStyle())
          .copyWith(
            textStyle: WidgetStatePropertyAll(
              (mobileTextTheme.labelLarge ?? const TextStyle()).copyWith(
                fontSize: 13.5,
                fontWeight: FontWeight.normal,
              ),
            ),
          ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: (baseTheme.elevatedButtonTheme.style ?? const ButtonStyle())
          .copyWith(
            textStyle: WidgetStatePropertyAll(
              (mobileTextTheme.labelLarge ?? const TextStyle()).copyWith(
                fontSize: 13.5,
                fontWeight: FontWeight.normal,
              ),
            ),
          ),
    ),
    popupMenuTheme: baseTheme.popupMenuTheme.copyWith(
      textStyle: mobileTextTheme.bodyMedium?.copyWith(
        fontSize: 13.5,
        fontWeight: FontWeight.normal,
      ),
    ),
  );
}

class _AdminTabContent extends StatelessWidget {
  final Widget child;
  final bool allowed;

  const _AdminTabContent({required this.child, this.allowed = true});

  @override
  Widget build(BuildContext context) {
    if (!allowed) {
      return ValueListenableBuilder<AppLocale>(
        valueListenable: I18n.localeListenable,
        builder: (context, locale, _) {
          return EmptyState(
            icon: Icons.lock_outline,
            message: AdminUiCopy.noModulePermissionFor(locale),
          );
        },
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1440),
            child: SizedBox(
              width: double.infinity,
              height: constraints.maxHeight,
              child: AppSecondaryControlTheme(
                child: _AdminGlassControlTheme(child: child),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AdminGlassControlTheme extends StatelessWidget {
  final Widget child;

  const _AdminGlassControlTheme({required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final controlText = appSecondaryControlTextStyle(
      context,
    ).copyWith(color: cs.onSurface, fontWeight: FontWeight.normal);
    final labelText = appSecondaryControlLabelStyle(
      context,
    ).copyWith(color: cs.onSurface, fontWeight: FontWeight.normal);
    final selectedFill = isDark
        ? cs.primary.withValues(alpha: 0.16)
        : cs.primary.withValues(alpha: 0.075);
    final selectedBorder = cs.primary.withValues(alpha: isDark ? 0.24 : 0.18);
    final selectedForeground = cs.onSurface;
    final defaultBorder = cs.outlineVariant.withValues(
      alpha: isDark ? 0.09 : 0.11,
    );
    final glassFill = isDark
        ? cs.surfaceContainerHighest.withValues(alpha: 0.28)
        : cs.surfaceContainerHighest.withValues(alpha: 0.36);
    final surfaceStyle = appSurfaceStyleOf(context);
    final cardFill = surfaceStyle?.cardFillColor ?? cs.surface;
    final cardBackground = Color.alphaBlend(
      cardFill,
      theme.scaffoldBackgroundColor,
    );
    final textButtonForeground = surfaceStyle != null
        ? appReadableForeground(cardBackground, cs.primary)
        : cs.primary;
    final buttonShape = surfaceStyle == null
        ? null
        : RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(surfaceStyle.smallTileRadius),
          );

    ButtonStyle adminTextButtonStyle() {
      return TextButton.styleFrom(
        foregroundColor: textButtonForeground,
        textStyle: controlText.copyWith(color: textButtonForeground),
        minimumSize: surfaceStyle != null
            ? const Size(44, 44)
            : const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        visualDensity: VisualDensity.standard,
        tapTargetSize: MaterialTapTargetSize.padded,
        shape: buttonShape,
      );
    }

    ButtonStyle adminOutlinedButtonStyle() {
      return OutlinedButton.styleFrom(
        foregroundColor: cs.onSurface,
        disabledForegroundColor: cs.onSurface.withValues(alpha: 0.36),
        side: BorderSide(color: defaultBorder, width: 0.45),
        textStyle: controlText,
        minimumSize: surfaceStyle != null
            ? const Size(44, 44)
            : const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        visualDensity: VisualDensity.standard,
        tapTargetSize: MaterialTapTargetSize.padded,
        shape: buttonShape,
      );
    }

    ButtonStyle adminFilledButtonStyle() {
      return FilledButton.styleFrom(
        backgroundColor: glassFill,
        foregroundColor: cs.onSurface,
        disabledBackgroundColor: glassFill.withValues(alpha: 0.42),
        disabledForegroundColor: cs.onSurface.withValues(alpha: 0.34),
        side: BorderSide(color: defaultBorder, width: 0.45),
        textStyle: controlText,
        minimumSize: surfaceStyle != null
            ? const Size(44, 44)
            : const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        visualDensity: VisualDensity.standard,
        tapTargetSize: MaterialTapTargetSize.padded,
        shape: buttonShape,
      );
    }

    return Theme(
      data: theme.copyWith(
        textButtonTheme: TextButtonThemeData(style: adminTextButtonStyle()),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: adminOutlinedButtonStyle(),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: adminFilledButtonStyle(),
        ),
        chipTheme: theme.chipTheme.copyWith(
          labelStyle: labelText.copyWith(color: cs.onSurface),
          secondaryLabelStyle: labelText.copyWith(color: selectedForeground),
          selectedColor: selectedFill,
          backgroundColor: glassFill.withValues(alpha: 0.72),
          disabledColor: glassFill.withValues(alpha: 0.36),
          checkmarkColor: selectedForeground,
          iconTheme: IconThemeData(size: 15, color: selectedForeground),
          side: BorderSide(color: defaultBorder, width: 0.45),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
            side: BorderSide(color: selectedBorder, width: 0.45),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        ),
      ),
      child: child,
    );
  }
}

class _AdminTabLabel extends StatelessWidget {
  final IconData icon;
  final String text;

  const _AdminTabLabel({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, locale, _) {
        final displayText = AdminUiCopy.tabTitle(text, locale);
        return ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 72),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16),
              const SizedBox(width: 5),
              Text(displayText),
            ],
          ),
        );
      },
    );
  }
}

/// Settings fields keep the input in one slot while long labels reflow.
class _AdminSettingsTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final InputDecoration decoration;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final bool enabled;
  final bool obscureText;
  final VoidCallback? onEditingComplete;

  const _AdminSettingsTextField({
    required this.controller,
    required this.label,
    required this.decoration,
    this.keyboardType,
    this.inputFormatters,
    this.enabled = true,
    this.obscureText = false,
    this.onEditingComplete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final external =
        media.size.width < 360 || media.textScaler.scale(1.0) > 1.25;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (external)
          ExcludeSemantics(
            child: Text(
              label,
              style:
                  (theme.inputDecorationTheme.labelStyle ??
                          theme.textTheme.bodyMedium ??
                          const TextStyle())
                      .copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.normal,
                      ),
            ),
          )
        else
          const SizedBox.shrink(),
        SizedBox(height: external ? 6 : 0),
        Semantics(
          label: external ? label : null,
          child: TextField(
            controller: controller,
            enabled: enabled,
            obscureText: obscureText,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            onEditingComplete: onEditingComplete,
            decoration: decoration.copyWith(
              labelText: external ? null : label,
              constraints:
                  decoration.constraints ?? const BoxConstraints(minHeight: 44),
            ),
          ),
        ),
      ],
    );
  }
}

class _AdminChipWrap extends StatelessWidget {
  final EdgeInsetsGeometry padding;
  final List<Widget> children;

  const _AdminChipWrap({
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(12, 0, 12, 8),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(spacing: 8, runSpacing: 6, children: children),
      ),
    );
  }
}

class _AdminCompactChipStrip extends StatelessWidget {
  final EdgeInsetsGeometry padding;
  final List<Widget> children;

  const _AdminCompactChipStrip({
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(12, 0, 12, 6),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: SingleChildScrollView(
        key: const ValueKey('admin_compact_chip_strip_horizontal'),
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final child in children) ...[child, const SizedBox(width: 6)],
          ],
        ),
      ),
    );
  }
}

Border _adminSubtleSectionBorder(BuildContext context) {
  final theme = Theme.of(context);
  final alpha = theme.brightness == Brightness.dark ? 0.07 : 0.026;
  return Border.all(
    color: theme.colorScheme.outline.withValues(alpha: alpha),
    width: 0.45,
  );
}

Border _adminSubtleListBorder(BuildContext context) {
  final theme = Theme.of(context);
  final alpha = theme.brightness == Brightness.dark ? 0.06 : 0.020;
  return Border.all(
    color: theme.colorScheme.outline.withValues(alpha: alpha),
    width: 0.45,
  );
}

class _AdminListTileCard extends StatelessWidget {
  final Widget? leading;
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry margin;
  final bool dense;

  const _AdminListTileCard({
    required this.title,
    this.leading,
    this.subtitle,
    this.trailing,
    this.margin = EdgeInsets.zero,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    return AppListTileCard(
      title: title,
      leading: leading,
      subtitle: subtitle,
      trailing: trailing,
      margin: margin,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      dense: dense,
      border: _adminSubtleListBorder(context),
      elevation: 0,
    );
  }
}

class _AdminSettingsSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;

  const _AdminSettingsSection({
    required this.title,
    required this.children,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return AppSettingsSection(
      title: title,
      subtitle: subtitle,
      border: _adminSubtleSectionBorder(context),
      elevation: 0,
      children: children,
    );
  }
}

class _AdminPermissionGroupPanel extends StatelessWidget {
  final _AdminPermissionGroup group;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final AppLocale? locale;

  const _AdminPermissionGroupPanel({
    required this.group,
    required this.selected,
    required this.onChanged,
    this.locale,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = locale ?? I18n.current;
    final visiblePermissions = group.permissions
        .where(_adminPermissionLabels.containsKey)
        .toList(growable: false);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: cs.outlineVariant.withValues(
            alpha: theme.brightness == Brightness.dark ? 0.12 : 0.14,
          ),
          width: 0.55,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(group.icon, size: 16, color: cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  AdminUiCopy.permissionGroupTitle(group.title, l),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            for (final permission in visiblePermissions)
              CheckboxListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                contentPadding: EdgeInsets.zero,
                value: selected.contains(permission),
                title: Text(AdminUiCopy.permissionLabel(permission, l)),
                onChanged: (value) {
                  final next = selected.toSet();
                  if (value == true) {
                    next.add(permission);
                  } else {
                    next.remove(permission);
                  }
                  onChanged(next);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _AdminGroupSummaryCard extends StatelessWidget {
  final Map<String, dynamic> group;
  final bool canManage;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final bool showDelete;

  const _AdminGroupSummaryCard({
    required this.group,
    required this.canManage,
    this.onEdit,
    this.onDelete,
    this.showDelete = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final active = group['is_active'] != false;
    final id = (group['id'] ?? '').toString();
    final name = (group['name'] ?? id).toString();
    final description = (group['description'] ?? '').toString().trim();
    final userCount = _adminIntValue(group['user_count']);
    final coins = _adminIntValue(group['default_time_coins']);
    final statusColor = active ? Colors.green : cs.onSurfaceVariant;
    return AppSurfaceCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      borderRadius: BorderRadius.circular(9),
      border: _adminSubtleListBorder(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: (active ? cs.primary : cs.onSurfaceVariant).withValues(
                alpha: 0.10,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.groups_2_outlined,
              color: active ? cs.primary : cs.onSurfaceVariant,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? AdminUiCopy.unnamedGroup : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.normal,
                  ),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.62),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  AdminUiCopy.groupCardCoinsLabel(coins),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.72),
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    AppStatusBadge(
                      label: AdminUiCopy.userCountLabel(userCount),
                      color: cs.primary,
                      icon: Icons.people_outline,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                    ),
                    AppStatusBadge(
                      label: active
                          ? AdminUiCopy.enabled
                          : AdminUiCopy.disabled,
                      color: statusColor,
                      icon: active
                          ? Icons.check_circle_outline
                          : Icons.pause_circle_outline,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (canManage)
            SizedBox(
              width: showDelete && id != 'group_default' ? 82 : 40,
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 2,
                children: [
                  IconButton(
                    tooltip: AdminUiCopy.editGroupTooltip,
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  if (showDelete && id != 'group_default')
                    IconButton(
                      key: ValueKey('admin_group_delete_$id'),
                      tooltip: AdminUiCopy.deleteGroupTooltip,
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _AdminMobileMetaItem extends StatelessWidget {
  final IconData icon;
  final String text;

  const _AdminMobileMetaItem({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cs.onSurfaceVariant),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.onSurface.withValues(alpha: 0.68),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminMobileMetric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _AdminMobileMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(
          alpha: theme.brightness == Brightness.dark ? 0.24 : 0.34,
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: cs.outlineVariant.withValues(
            alpha: theme.brightness == Brightness.dark ? 0.08 : 0.10,
          ),
          width: 0.45,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 15, color: cs.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.58),
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                  value.length > 8
                      ? FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.onSurface,
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                        )
                      : Text(
                          value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ====================================================================
// 概览
// ====================================================================

class _DashboardTab extends StatefulWidget {
  final AdminApi api;
  const _DashboardTab({super.key, required this.api});
  @override
  State<_DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<_DashboardTab> {
  Map<String, dynamic>? _stats;
  Object? _errorObject;
  bool _loading = true;
  int _loadSerial = 0;

  @override
  void initState() {
    super.initState();
    I18n.localeListenable.addListener(_handleLocaleChanged);
    _load();
  }

  @override
  void dispose() {
    I18n.localeListenable.removeListener(_handleLocaleChanged);
    super.dispose();
  }

  void _handleLocaleChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final serial = ++_loadSerial;
    setState(() {
      _loading = true;
      _errorObject = null;
    });
    try {
      final res = await widget.api.stats();
      if (!mounted || serial != _loadSerial) return;
      setState(() {
        _stats = res;
        _errorObject = null;
      });
    } on ApiException catch (e) {
      if (!mounted || serial != _loadSerial) return;
      setState(() => _errorObject = e);
    } catch (e) {
      if (!mounted || serial != _loadSerial) return;
      setState(() => _errorObject = e);
    } finally {
      if (mounted && serial == _loadSerial) {
        setState(() => _loading = false);
      }
    }
  }

  String? get _error {
    final err = _errorObject;
    if (err == null) return null;
    if (err is ApiException) {
      return userVisibleApiError(err);
    }
    return _adminErrorMessage(err, AdminUiCopy.dashboardData);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _stats == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_stats == null) {
      return _AdminErrorState(
        message: _error ?? AdminUiCopy.dashboardLoadFailed,
        onRetry: _load,
      );
    }
    final users = _stats!['users'] as Map? ?? {};
    final fb = _stats!['feedback'] as Map? ?? {};
    final ann = _stats!['announcements'] as Map? ?? {};
    final inv = _stats!['invites'] as Map? ?? {};
    final series = (_stats!['registration_series'] as List?)?.cast<Map>() ?? [];
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (_error != null)
            AppSurfaceCard(
              color: cs.errorContainer.withValues(alpha: 0.35),
              border: Border.all(
                color: cs.error.withValues(alpha: 0.5),
                width: 0.55,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              margin: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: cs.error, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      AdminUiCopy.dashboardRefreshFailedWith(_error!),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.error,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _loading ? null : _load,
                    child: Text(AdminUiCopy.retry),
                  ),
                ],
              ),
            ),
          _AdminInlineLoadingIndicator(
            visible: _loading && _stats != null,
            label: AdminUiCopy.updatingDashboardData,
          ),
          AppInfoBanner(
            icon: Icons.verified_outlined,
            color: Colors.indigo,
            title: AdminUiCopy.clientConnection,
            message: AppConfig.bakedServerUrl.isEmpty
                ? AdminUiCopy.relativeSameOriginProxy
                : AppConfig.bakedServerUrl,
            margin: const EdgeInsets.only(bottom: 12),
          ),
          _GridCards([
            _Kpi(
              AdminUiCopy.kpiTotalUsers,
              users['total'] == null ? '-' : '${users['total']}',
              Icons.people,
              Colors.blue,
            ),
            _Kpi(
              AdminUiCopy.kpiAdmins,
              users['admin'] == null ? '-' : '${users['admin']}',
              Icons.shield,
              Colors.deepOrange,
            ),
            _Kpi(
              AdminUiCopy.kpiDisabled,
              users['disabled'] == null ? '-' : '${users['disabled']}',
              Icons.block,
              cs.error,
            ),
            _Kpi(
              AdminUiCopy.kpiNewToday,
              users['new_today'] == null ? '-' : '${users['new_today']}',
              Icons.person_add_alt,
              Colors.green,
            ),
            _Kpi(
              AdminUiCopy.kpiActive7d,
              users['active_7d'] == null ? '-' : '${users['active_7d']}',
              Icons.trending_up,
              Colors.teal,
            ),
            _Kpi(
              AdminUiCopy.kpiOnline,
              (users['online'] ?? _stats!['tokens_online']) == null
                  ? '-'
                  : '${users['online'] ?? _stats!['tokens_online']}',
              Icons.wifi_tethering,
              Colors.cyan,
            ),
            _Kpi(
              AdminUiCopy.kpiUnverifiedEmail,
              users['unverified_email'] == null
                  ? '-'
                  : '${users['unverified_email']}',
              Icons.mark_email_unread_outlined,
              Colors.amber,
            ),
            _Kpi(
              AdminUiCopy.kpiOpenFeedback,
              fb['open'] == null ? '-' : '${fb['open']}',
              Icons.chat_bubble_outline,
              Colors.orange,
            ),
            _Kpi(
              AdminUiCopy.kpiInProgressFeedback,
              fb['in_progress'] == null ? '-' : '${fb['in_progress']}',
              Icons.pending_actions_outlined,
              Colors.deepPurple,
            ),
            _Kpi(
              AdminUiCopy.kpiTotalFeedback,
              fb['total'] == null ? '-' : '${fb['total']}',
              Icons.forum_outlined,
              Colors.grey,
            ),
            _Kpi(
              AdminUiCopy.kpiPublishedAnnouncements,
              ann['published'] == null ? '-' : '${ann['published']}',
              Icons.campaign,
              Colors.indigo,
            ),
            _Kpi(
              AdminUiCopy.kpiInvitesUsed,
              inv['used'] == null && inv['total'] == null
                  ? '-'
                  : '${inv['used'] ?? '-'} / ${inv['total'] ?? '-'}',
              Icons.vpn_key,
              Colors.purple,
            ),
          ]),
          const SizedBox(height: 14),
          AppSurfaceCard(
            padding: const EdgeInsets.all(14),
            child: Padding(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AdminUiCopy.recentRegistrations7d,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (series.isEmpty)
                    Text(
                      AdminUiCopy.noRegistrations,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.58),
                      ),
                    ),
                  ...series.map((row) {
                    final count = ((row['count'] as num?) ?? 0).toDouble();
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 90,
                            child: Text(
                              row['date'].toString(),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurface.withValues(alpha: 0.68),
                                fontWeight: FontWeight.normal,
                              ),
                            ),
                          ),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: (count / 10).clamp(0.0, 1.0),
                                minHeight: 8,
                                backgroundColor: cs.surfaceContainerHighest,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${row['count']}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurface,
                              fontWeight: FontWeight.normal,
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
        ],
      ),
    );
  }
}

class _Kpi {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  const _Kpi(this.title, this.value, this.icon, this.color);
}

class _GridCards extends StatelessWidget {
  final List<_Kpi> items;
  const _GridCards(this.items);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = Theme.of(context).colorScheme;
    final isMobile = MediaQuery.sizeOf(context).width < 600;

    Widget buildCard(_Kpi k) {
      return AppSurfaceCard(
        padding: const EdgeInsets.all(12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: k.color.withValues(alpha: 0.16), width: 0.45),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: k.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(k.icon, color: k.color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    k.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    softWrap: true,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.62),
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                  k.value.length > 8
                      ? FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            k.value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: cs.onSurface,
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                        )
                      : Text(
                          k.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (!isMobile) {
      return GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        childAspectRatio: 2.4,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        children: items.map(buildCard).toList(),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final textScaler = MediaQuery.textScalerOf(context);
        final isLargeText = textScaler.scale(1.0) >= 1.25;
        final isNarrow = constraints.maxWidth < 360;
        final crossAxisCount = (isNarrow || isLargeText) ? 1 : 2;
        final bodySmall = theme.textTheme.bodySmall;
        final titleMedium = theme.textTheme.titleMedium;
        final titleHeight =
            textScaler.scale(bodySmall?.fontSize ?? 12.5) *
            (bodySmall?.height ?? 1.5) *
            2;
        final valueHeight =
            textScaler.scale(titleMedium?.fontSize ?? 14.0) *
            (titleMedium?.height ?? 1.28);
        final textHeight = titleHeight + valueHeight;
        final contentHeight = textHeight > 38.0 ? textHeight : 38.0;
        final computedExtent = (24.0 + contentHeight).ceilToDouble() + 2.0;
        final baseExtent = crossAxisCount == 1
            ? 68.0
            : (constraints.maxWidth < 340 ? 82.0 : 80.0);
        final mainAxisExtent = computedExtent > baseExtent
            ? computedExtent
            : baseExtent;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            mainAxisExtent: mainAxisExtent,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) => buildCard(items[index]),
        );
      },
    );
  }
}

const int _adminPageSize = 20;
const List<int> _adminPageSizeOptions = [20, 50, 100, 200];
const String _adminUpdatePresetCurrent = 'current';
const String _adminUpdatePresetNextPatch = 'next_patch';
const String _adminUpdatePresetNextMinor = 'next_minor';
const String _adminUpdatePresetMinimumNextPatch = 'minimum_next_patch';
const String _adminAllPermission = '*';
const String _adminNoPermission = '__none__';
const Map<String, String> _adminPermissionLabels = {
  'settings': '全站设置',
  'users': '用户',
  'coins': '时光币',
  'backup': '备份',
  'ai': 'AI',
  'announcements': '公告',
  'feedback': '反馈',
  'invites': '邀请码',
  'audit': '日志',
  'groups': '用户组',
  'roles': '角色',
  'permissions': '权限字典',
};

class _AdminPermissionGroup {
  final String title;
  final IconData icon;
  final List<String> permissions;

  const _AdminPermissionGroup({
    required this.title,
    required this.icon,
    required this.permissions,
  });
}

const List<_AdminPermissionGroup> _adminPermissionGroups = [
  _AdminPermissionGroup(
    title: '基础功能',
    icon: Icons.tune,
    permissions: ['settings', 'announcements', 'invites'],
  ),
  _AdminPermissionGroup(
    title: '个人数据',
    icon: Icons.person_search_outlined,
    permissions: ['users', 'coins', 'backup', 'feedback'],
  ),
  _AdminPermissionGroup(
    title: '管理功能',
    icon: Icons.admin_panel_settings_outlined,
    permissions: ['groups', 'roles', 'permissions'],
  ),
  _AdminPermissionGroup(
    title: '系统功能',
    icon: Icons.memory_outlined,
    permissions: ['ai', 'audit'],
  ),
];

Set<String> _adminAllPermissionKeys() => _adminPermissionLabels.keys.toSet();

bool _adminHasAllPermissions(Set<String> selected) {
  return _adminPermissionLabels.keys.every(selected.contains);
}

String _adminStatusLabel(String value, [AppLocale? locale]) {
  return AdminUiCopy.statusLabel(value, locale);
}

class _AdminUpdateVersionOption {
  final String key;
  final String label;
  final String latestVersion;
  final String minimumSupportedVersion;

  const _AdminUpdateVersionOption({
    required this.key,
    required this.label,
    required this.latestVersion,
    required this.minimumSupportedVersion,
  });
}

String _adminUserSortLabel(String sort) => switch (sort) {
  'last_active_desc' => _userText('最近活跃优先', 'Recently active'),
  'last_login_desc' => _userText('最近登录优先', 'Recent sign in'),
  'feedback_desc' => _userText('反馈较多优先', 'Most feedback'),
  'username_asc' => _userText('用户名 A-Z', 'Username A–Z'),
  'email_asc' => _userText('邮箱 A-Z', 'Email A–Z'),
  _ => _userText('最新注册优先', 'Newest accounts'),
};

List<String> _adminUserPermissions(dynamic raw, {required bool isAdmin}) {
  if (raw is List) {
    final values = raw.map((e) => e.toString()).where((e) => e.isNotEmpty);
    if (values.contains(_adminNoPermission)) return const [];
    final normalized = <String>[];
    for (final value in values) {
      if (value == _adminNoPermission) return const [];
      if (value == _adminAllPermission) return const [_adminAllPermission];
      if (_adminPermissionLabels.containsKey(value) &&
          !normalized.contains(value)) {
        normalized.add(value);
      }
    }
    if (normalized.isNotEmpty) return normalized;
  }
  return isAdmin ? const [_adminAllPermission] : const [];
}

String _adminPermissionsLabel(
  List<String> permissions, {
  required bool isAdmin,
  AppLocale? locale,
}) {
  final l = locale ?? I18n.current;
  final zh = l == AppLocale.zh;
  if (!isAdmin) return AdminUiCopy.noAdminPermissionsFor(l);
  if (permissions.contains(_adminAllPermission)) {
    return AdminUiCopy.allPermissionsFor(l);
  }
  if (permissions.isEmpty) return AdminUiCopy.noAdminPermissionsFor(l);
  final separator = zh ? '、' : ', ';
  return permissions
      .map((key) => AdminUiCopy.permissionLabel(key, l))
      .join(separator);
}

int _adminIntValue(dynamic raw) {
  if (raw is num) return raw.toInt();
  return int.tryParse(raw?.toString() ?? '') ?? 0;
}

int _adminIntValueOrDefault(dynamic raw, int fallback) {
  if (raw == null) return fallback;
  if (raw is String && raw.trim().isEmpty) return fallback;
  return _adminIntValue(raw);
}

String _adminIntValueOrDash(dynamic raw) {
  if (raw == null) return '-';
  if (raw is String && raw.trim().isEmpty) return '-';
  return _adminIntValue(raw).toString();
}

String _adminAnnouncementSortLabel(String value, [AppLocale? locale]) {
  return AdminAnnouncementUiCopy.sortLabel(value, locale);
}

String _adminFeedbackSortLabel(String value, [AppLocale? locale]) =>
    AdminFeedbackUiCopy.sortLabel(value, locale);

String _adminInviteSortLabel(String value, [AppLocale? locale]) =>
    AdminInviteUiCopy.sortLabel(value, locale);

String _adminAuditSortLabel(String value, [AppLocale? locale]) =>
    AdminAuditUiCopy.sortLabel(value, locale);

String _adminBackupSortLabel(String value, [AppLocale? locale]) {
  return AdminUiCopy.backupSortLabel(value, locale);
}

String _adminServerBackupSortLabel(String value, [AppLocale? locale]) {
  return AdminUiCopy.serverBackupSortOptionLabel(value, locale);
}

String _auditActionLabel(String value, [AppLocale? locale]) =>
    AdminAuditUiCopy.actionLabel(value, locale);

String _feedbackCategoryLabel(String value, [AppLocale? locale]) =>
    AdminFeedbackUiCopy.categoryLabel(value, locale);

String _adminPageSummary(AdminPage? page, [AppLocale? locale]) {
  final effectiveLocale = locale ?? I18n.current;
  final zh = effectiveLocale == AppLocale.zh;
  if (page == null) return zh ? '正在加载本页数据' : 'Loading page data...';
  if (page.total <= 0) return zh ? '0 条' : '0 items';
  final safeLimit = page.limit <= 0 ? _adminPageSize : page.limit;
  final maxOffset = ((page.total - 1) ~/ safeLimit) * safeLimit;
  final safeOffset = page.offset.clamp(0, maxOffset).toInt();
  final start = safeOffset + 1;
  final end = (safeOffset + page.items.length).clamp(start, page.total).toInt();
  return zh
      ? '第 $start-$end 条 / 共 ${page.total} 条'
      : '$start-$end of ${page.total}';
}

String _adminPageNumber(AdminPage? page, [AppLocale? locale]) {
  final effectiveLocale = locale ?? I18n.current;
  final zh = effectiveLocale == AppLocale.zh;
  if (page == null) return zh ? '第 -/- 页' : 'Page -/-';
  if (page.total <= 0) return zh ? '第 0/0 页' : 'Page 0/0';
  final safeLimit = page.limit <= 0 ? _adminPageSize : page.limit;
  final totalPages = ((page.total + safeLimit - 1) ~/ safeLimit).clamp(
    1,
    999999,
  );
  final current = ((page.offset ~/ safeLimit) + 1).clamp(1, totalPages).toInt();
  return zh ? '第 $current/$totalPages 页' : 'Page $current/$totalPages';
}

int _adminTotalPages(AdminPage? page, int pageSize) {
  if (page == null || page.total <= 0) return 0;
  final safeLimit = pageSize <= 0 ? _adminPageSize : pageSize;
  return ((page.total + safeLimit - 1) ~/ safeLimit).clamp(1, 999999);
}

int _previousAdminOffset(int offset, [int pageSize = _adminPageSize]) {
  return offset <= pageSize ? 0 : offset - pageSize;
}

int _offsetAfterAdminDelete({
  required int offset,
  required int itemCount,
  int pageSize = _adminPageSize,
}) {
  if (itemCount == 1 && offset > 0) {
    return _previousAdminOffset(offset, pageSize);
  }
  return offset;
}

int _lastAdminOffset({required int total, required int pageSize}) {
  if (total <= 0) return 0;
  final safeLimit = pageSize <= 0 ? _adminPageSize : pageSize;
  return ((total - 1) ~/ safeLimit) * safeLimit;
}

String _adminErrorMessage(Object error, String target, [AppLocale? locale]) {
  return AdminUiCopy.formatLoadError(error, target, locale: locale);
}

String _adminActionErrorMessage(
  Object error,
  String action, [
  AppLocale? locale,
]) {
  return AdminUiCopy.formatActionError(error, action, locale: locale);
}

class _AdminFeedbackText extends StatelessWidget {
  const _AdminFeedbackText(this.message);

  final String Function(AppLocale locale) message;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppLocale>(
    valueListenable: I18n.localeListenable,
    builder: (context, locale, _) => Text(message(locale)),
  );
}

Widget _adminResponsiveTwoColumn({
  required BuildContext context,
  required Widget first,
  required Widget second,
  double breakpoint = 460,
  double gap = 10,
}) {
  return LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < breakpoint) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            first,
            SizedBox(height: gap),
            second,
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: first),
          SizedBox(width: gap),
          Expanded(child: second),
        ],
      );
    },
  );
}

List<Widget> _adminDialogChildren(List<Widget> children, {double gap = 10}) {
  final separated = <Widget>[];
  for (final child in children) {
    if (separated.isNotEmpty) separated.add(SizedBox(height: gap));
    separated.add(child);
  }
  return separated;
}

Widget _adminDialogForm({
  double maxWidth = 460,
  required List<Widget> children,
}) {
  final constraints = maxWidth == 430
      ? const BoxConstraints(maxWidth: 430)
      : maxWidth == 420
      ? const BoxConstraints(maxWidth: 420)
      : maxWidth == 400
      ? const BoxConstraints(maxWidth: 400)
      : BoxConstraints(maxWidth: maxWidth);
  return ConstrainedBox(
    constraints: constraints,
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _adminDialogChildren(children),
      ),
    ),
  );
}

List<Widget> _adminDialogActions(
  BuildContext context, {
  String? saveLabel,
  AppLocale? locale,
}) {
  final l = locale ?? I18n.current;
  return [
    TextButton(
      onPressed: () => Navigator.pop(context, false),
      child: Text(AdminUiCopy.cancelFor(l)),
    ),
    FilledButton(
      onPressed: () => Navigator.pop(context, true),
      child: Text(saveLabel ?? AdminUiCopy.saveFor(l)),
    ),
  ];
}

Widget _adminPermissionChecklist({
  required Set<String> selected,
  required ValueChanged<Set<String>> onChanged,
  AppLocale? locale,
}) {
  final allSelected = _adminHasAllPermissions(selected);
  final l = locale ?? I18n.current;
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        value: allSelected,
        title: Text(AdminUiCopy.allPermissionsFor(l)),
        onChanged: (value) =>
            onChanged(value == true ? _adminAllPermissionKeys() : <String>{}),
      ),
      const SizedBox(height: 4),
      for (final group in _adminPermissionGroups) ...[
        _AdminPermissionGroupPanel(
          group: group,
          selected: selected,
          onChanged: onChanged,
          locale: l,
        ),
        const SizedBox(height: 8),
      ],
    ],
  );
}

class _AdminErrorState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _AdminErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final content = Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 40,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(AdminUiCopy.reload),
              ),
            ],
          ),
        );
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.hasBoundedHeight
                  ? constraints.maxHeight
                  : 0,
            ),
            child: Center(child: content),
          ),
        );
      },
    );
  }
}

class _AdminInlineLoadingIndicator extends StatelessWidget {
  final bool visible;
  final String label;

  const _AdminInlineLoadingIndicator({
    required this.visible,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 160),
      child: visible
          ? Padding(
              key: ValueKey(label),
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      backgroundColor: cs.surfaceContainerHighest,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.58),
                    ),
                  ),
                ],
              ),
            )
          : const SizedBox(key: ValueKey('idle'), height: 0),
    );
  }
}

class _AdminPaginationBar extends StatelessWidget {
  final Key? barKey;
  final AdminPage? page;
  final bool loading;
  final int pageSize;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<int>? onJumpToPage;
  final ValueChanged<int>? onPageSizeChanged;
  final AppLocale? locale;

  const _AdminPaginationBar({
    this.barKey,
    required this.page,
    required this.loading,
    this.pageSize = _adminPageSize,
    required this.onPrevious,
    required this.onNext,
    this.onJumpToPage,
    this.onPageSizeChanged,
    this.locale,
  });

  @override
  Widget build(BuildContext context) {
    final canPrevious = !loading && (page?.offset ?? 0) > 0;
    final canNext = !loading && (page?.hasMore ?? false);
    final totalPages = _adminTotalPages(page, pageSize);
    final canPickPage =
        onJumpToPage != null && totalPages > 1 && totalPages <= 200;
    final currentPage = totalPages <= 0 || page == null
        ? 0
        : (page!.offset ~/ (page!.limit <= 0 ? pageSize : page!.limit)) + 1;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final topBorderColor = cs.outlineVariant.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.14 : 0.16,
    );
    final summaryTextStyle = appSecondaryControlLabelStyle(
      context,
    ).copyWith(color: cs.onSurface.withValues(alpha: 0.64));
    final glassControlFill = theme.brightness == Brightness.dark
        ? cs.surfaceContainerHighest.withValues(alpha: 0.30)
        : cs.surfaceContainerHighest.withValues(alpha: 0.38);
    final glassControlBorder = cs.outlineVariant.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.09 : 0.11,
    );
    return Container(
      key: barKey,
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.92),
        border: Border(top: BorderSide(color: topBorderColor, width: 0.55)),
      ),
      child: ValueListenableBuilder<AppLocale>(
        valueListenable: I18n.localeListenable,
        builder: (context, activeLocale, _) {
          return LayoutBuilder(
            builder: (context, constraints) {
              final locale = this.locale ?? activeLocale;
              final isVeryCompact = constraints.maxWidth < 420;
              final summary = Text(
                '${_adminPageSummary(page, locale)} · ${_adminPageNumber(page, locale)}',
                maxLines: isVeryCompact ? null : 1,
                overflow: isVeryCompact ? null : TextOverflow.ellipsis,
                style: summaryTextStyle,
              );
              final pageSizePicker = onPageSizeChanged == null
                  ? null
                  : _AdminPaginationLabeledControl(
                      label: AdminUiCopy.perPageFor(locale),
                      child: AppCompactDropdown<int>(
                        width: 54,
                        value: pageSize,
                        items: _adminPageSizeOptions
                            .map(
                              (v) =>
                                  DropdownMenuItem(value: v, child: Text('$v')),
                            )
                            .toList(),
                        onChanged: loading || onPageSizeChanged == null
                            ? null
                            : (v) {
                                if (v != null) onPageSizeChanged!(v);
                              },
                      ),
                    );
              final pageJump = !canPickPage
                  ? null
                  : _AdminPaginationLabeledControl(
                      label: AdminUiCopy.pageNumberFor(locale),
                      child: AppCompactDropdown<int>(
                        width: 76,
                        value: currentPage.clamp(1, totalPages).toInt(),
                        items: List.generate(
                          totalPages > 200 ? 200 : totalPages,
                          (index) {
                            final pageNo = index + 1;
                            return DropdownMenuItem(
                              value: pageNo,
                              child: Text('$pageNo/$totalPages'),
                            );
                          },
                        ),
                        onChanged: loading
                            ? null
                            : (value) {
                                if (value != null) onJumpToPage!(value);
                              },
                      ),
                    );
              Widget navigation() {
                Widget navButton({
                  required String message,
                  required IconData icon,
                  required VoidCallback? onPressed,
                }) {
                  return Tooltip(
                    message: message,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: SizedBox.square(
                        dimension: 32,
                        child: IconButton(
                          constraints: const BoxConstraints.tightFor(
                            width: 32,
                            height: 32,
                          ),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          iconSize: 16,
                          style: IconButton.styleFrom(
                            backgroundColor: onPressed == null
                                ? Colors.transparent
                                : glassControlFill,
                            disabledBackgroundColor: Colors.transparent,
                            side: BorderSide(
                              color: onPressed == null
                                  ? glassControlBorder.withValues(alpha: 0.50)
                                  : glassControlBorder,
                              width: 0.45,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                DesignTokens.radiusControl,
                              ),
                            ),
                          ),
                          onPressed: onPressed,
                          icon: Icon(icon),
                        ),
                      ),
                    ),
                  );
                }

                final hasPageShortcuts = onJumpToPage != null && totalPages > 1;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasPageShortcuts)
                      navButton(
                        message: AdminUiCopy.jumpToFirstPageFor(locale),
                        icon: Icons.first_page,
                        onPressed: canPrevious ? () => onJumpToPage!(1) : null,
                      ),
                    navButton(
                      message: AdminUiCopy.previousPageFor(locale),
                      icon: Icons.chevron_left,
                      onPressed: canPrevious ? onPrevious : null,
                    ),
                    navButton(
                      message: AdminUiCopy.nextPageFor(locale),
                      icon: Icons.chevron_right,
                      onPressed: canNext ? onNext : null,
                    ),
                    if (hasPageShortcuts)
                      navButton(
                        message: AdminUiCopy.jumpToLastPageFor(locale),
                        icon: Icons.last_page,
                        onPressed: canNext
                            ? () => onJumpToPage!(totalPages)
                            : null,
                      ),
                  ],
                );
              }

              final isCompact = constraints.maxWidth < 720;
              final fullControls = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (pageJump != null) ...[pageJump, const SizedBox(width: 6)],
                  if (pageSizePicker != null) ...[
                    pageSizePicker,
                    const SizedBox(width: 6),
                  ],
                  Tooltip(
                    message: AdminUiCopy.paginationNavigationFor(locale),
                    child: navigation(),
                  ),
                ],
              );
              final compactControls = Wrap(
                key: const ValueKey('admin_compact_pagination_controls'),
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                runSpacing: 6,
                children: [
                  ?pageJump,
                  ?pageSizePicker,
                  Tooltip(
                    message: AdminUiCopy.paginationNavigationFor(locale),
                    child: navigation(),
                  ),
                ],
              );
              if (isCompact) {
                if (isVeryCompact) {
                  return SizedBox(
                    width: double.infinity,
                    key: const ValueKey('admin_compact_pagination_full_width'),
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        summary,
                        Tooltip(
                          message: AdminUiCopy.paginationNavigationFor(locale),
                          child: navigation(),
                        ),
                      ],
                    ),
                  );
                }
                return SizedBox(
                  width: double.infinity,
                  key: const ValueKey('admin_compact_pagination_full_width'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        runSpacing: 4,
                        spacing: 8,
                        children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 300),
                            child: summary,
                          ),
                          compactControls,
                        ],
                      ),
                    ],
                  ),
                );
              }
              return SizedBox(
                width: double.infinity,
                child: Row(
                  children: [
                    Expanded(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 360),
                        child: summary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    fullControls,
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _AdminPaginationLabeledControl extends StatelessWidget {
  final String label;
  final Widget child;

  const _AdminPaginationLabeledControl({
    required this.label,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark
        ? cs.surfaceContainerHighest.withValues(alpha: 0.34)
        : cs.surfaceContainerHighest.withValues(alpha: 0.48);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(DesignTokens.radiusControl),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: isDark ? 0.14 : 0.16),
          width: 0.55,
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 68, minHeight: 32),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: appSecondaryControlLabelStyle(
                  context,
                ).copyWith(color: cs.onSurface.withValues(alpha: 0.68)),
              ),
              const SizedBox(width: 4),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupsTab extends StatefulWidget {
  final AdminApi api;
  final List<String>? selfAdminPermissions;

  const _GroupsTab({
    super.key,
    required this.api,
    required this.selfAdminPermissions,
  });

  @override
  State<_GroupsTab> createState() => _GroupsTabState();
}

class _GroupsTabState extends State<_GroupsTab> {
  final List<Map<String, dynamic>> _groups = [];
  final _actionHost = AdminActionHost();
  AdminPage? _page;
  bool _loading = true;
  bool _mutationPending = false;
  Object? _error;
  int _offset = 0;
  int _pageSize = _adminPageSize;
  int _loadSerial = 0;
  int? _authorityRevision;
  Future<void> Function()? _failedLoad;

  bool get _canManageGroups {
    final permissions = widget.selfAdminPermissions;
    return permissions == null ||
        (!permissions.contains(_adminNoPermission) &&
            (permissions.contains(_adminAllPermission) ||
                permissions.contains('groups')));
  }

  AdminActionOrigin _captureRead() => _actionHost.capture(
    client: widget.api.client,
    anyOfPermissions: const {'groups', 'users', 'coins'},
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _actionHost.bind(context);
    final revision = _actionHost.revision;
    if (_authorityRevision != revision) {
      _authorityRevision = revision;
      _loadSerial++;
      _groups.clear();
      _page = null;
      _failedLoad = null;
      _error = null;
      final origin = _captureRead();
      if (origin.isCurrent()) {
        _load(origin: origin, offset: 0);
      } else {
        _loading = false;
      }
    }
  }

  @override
  void dispose() {
    _loadSerial++;
    _actionHost.dispose();
    super.dispose();
  }

  Future<bool> _load({
    required AdminActionOrigin origin,
    AdminActionOrigin? mutationOrigin,
    int? pageSize,
    int? offset,
  }) async {
    bool current() =>
        mounted && origin.isCurrent() && (mutationOrigin?.isCurrent() ?? true);
    if (!current()) return false;
    final serial = ++_loadSerial;
    final nextPageSize = pageSize ?? _pageSize;
    final nextOffset = offset ?? _offset;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await AdminApi(origin.client).listGroupsPage(
        limit: nextPageSize,
        offset: nextOffset,
        isCurrent: current,
      );
      if (!current() || serial != _loadSerial) return false;
      _page = page;
      _pageSize = nextPageSize;
      _offset = nextOffset;
      _failedLoad = null;
      _groups
        ..clear()
        ..addAll(page.items);
      return true;
    } catch (error) {
      if (!current() || serial != _loadSerial) return false;
      _error = error;
      _failedLoad = () async {
        await _load(
          origin: origin,
          mutationOrigin: mutationOrigin,
          pageSize: nextPageSize,
          offset: nextOffset,
        );
      };
      return false;
    } finally {
      if (mounted && serial == _loadSerial) setState(() => _loading = false);
    }
  }

  void _showSnack(
    AdminActionOrigin origin,
    String Function(AppLocale) message,
  ) {
    if (!mounted || !origin.isCurrent()) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: _AdminFeedbackText(message)));
  }

  // A retained callback may only close the dialog route that rendered it.
  bool _closeDialog(
    BuildContext dialogContext,
    ModalRoute<dynamic> route,
    AdminActionOrigin origin,
    bool confirmed,
  ) {
    if (!dialogContext.mounted ||
        !route.isActive ||
        !route.isCurrent ||
        (confirmed && !origin.isCurrent(checkRoute: false))) {
      return false;
    }
    Navigator.of(dialogContext).pop(confirmed);
    return true;
  }

  Future<void> _editGroup(
    AdminActionOrigin origin, [
    Map<String, dynamic>? group,
  ]) async {
    if (_mutationPending || !origin.isCurrent()) return;
    if (!_canManageGroups) {
      _showSnack(origin, AdminUiCopy.missingGroupsPermissionFor);
      return;
    }
    setState(() => _mutationPending = true);
    final nameCtrl = TextEditingController(
      text: (group?['name'] ?? '').toString(),
    );
    final descCtrl = TextEditingController(
      text: (group?['description'] ?? '').toString(),
    );
    final coinsCtrl = TextEditingController(
      text: _adminIntValueOrDefault(
        group?['default_time_coins'],
        100,
      ).toString(),
    );
    var isActive = group?['is_active'] != false;
    DialogRoute<bool>? dialogRoute;
    try {
      dialogRoute = DialogRoute<bool>(
        context: context,
        builder: (ctx) => ValueListenableBuilder<AppLocale>(
          valueListenable: I18n.localeListenable,
          builder: (ctx, locale, _) => StatefulBuilder(
            builder: (ctx, setSt) => AppDialog(
              title: Text(
                group == null
                    ? AdminUiCopy.addGroupTitleFor(locale)
                    : AdminUiCopy.editGroupTitleFor(locale),
              ),
              icon: const Icon(Icons.groups_2_outlined),
              content: _adminDialogForm(
                maxWidth: 430,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: AdminUiCopy.groupNameLabelFor(locale),
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  TextField(
                    controller: descCtrl,
                    decoration: InputDecoration(
                      labelText: AdminUiCopy.groupDescriptionLabelFor(locale),
                      helperText: AdminUiCopy.groupDescriptionHelperFor(locale),
                      helperMaxLines: 4,
                    ),
                    maxLines: 2,
                  ),
                  TextField(
                    controller: coinsCtrl,
                    decoration: InputDecoration(
                      labelText: AdminUiCopy.groupDefaultCoinsLabelFor(locale),
                      helperText: AdminUiCopy.groupDefaultCoinsHelperFor(
                        locale,
                      ),
                      helperMaxLines: 4,
                      prefixIcon: const Icon(Icons.toll_outlined),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: isActive,
                    title: Text(AdminUiCopy.groupEnableLabelFor(locale)),
                    subtitle: Text(AdminUiCopy.groupEnableSubtitleFor(locale)),
                    onChanged: (value) {
                      if (origin.isCurrent(checkRoute: false) &&
                          dialogRoute!.isCurrent &&
                          dialogRoute.isActive) {
                        setSt(() => isActive = value);
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () =>
                      _closeDialog(ctx, dialogRoute!, origin, false),
                  child: Text(AdminUiCopy.cancelFor(locale)),
                ),
                FilledButton(
                  onPressed: () {
                    if (!origin.isCurrent(checkRoute: false) ||
                        !dialogRoute!.isActive ||
                        !dialogRoute.isCurrent) {
                      return;
                    }
                    if (nameCtrl.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: _AdminFeedbackText(
                            AdminUiCopy.pleaseEnterGroupNameFor,
                          ),
                        ),
                      );
                      return;
                    }
                    _closeDialog(ctx, dialogRoute, origin, true);
                  },
                  child: Text(AdminUiCopy.saveFor(locale)),
                ),
              ],
            ),
          ),
        ),
      );
      final saved = await Navigator.of(context).push(dialogRoute);
      await dialogRoute.completed;
      if (saved != true || !origin.isCurrent()) return;
      await AdminApi(origin.client).saveGroup(
        id: group?['id']?.toString(),
        name: nameCtrl.text.trim(),
        description: descCtrl.text.trim(),
        defaultTimeCoins: (int.tryParse(coinsCtrl.text.trim()) ?? 100).clamp(
          0,
          1000000,
        ),
        isActive: isActive,
        isCurrent: origin.isCurrent,
      );
      if (!origin.isCurrent()) return;
      final reloaded = await _load(
        origin: _captureRead(),
        mutationOrigin: origin,
        offset: _offset,
      );
      if (origin.isCurrent()) {
        _showSnack(
          origin,
          (locale) => reloaded
              ? AdminUiCopy.groupSavedFor(locale)
              : AdminUiCopy.groupSavedRefreshFailedFor(locale),
        );
      }
    } catch (error) {
      _showSnack(
        origin,
        (locale) => _adminActionErrorMessage(
          error,
          AdminUiCopy.actionSaveGroupFor(locale),
          locale,
        ),
      );
    } finally {
      if (dialogRoute != null) await dialogRoute.completed;
      nameCtrl.dispose();
      descCtrl.dispose();
      coinsCtrl.dispose();
      if (mounted) setState(() => _mutationPending = false);
    }
  }

  Future<void> _deleteGroup(
    AdminActionOrigin origin,
    Map<String, dynamic> group,
  ) async {
    if (_mutationPending || !origin.isCurrent()) return;
    final id = (group['id'] ?? '').toString();
    if (id.isEmpty) return;
    if (id == 'group_default') {
      _showSnack(origin, AdminUiCopy.defaultGroupCannotDeleteFor);
      return;
    }
    final name = (group['name'] ?? id).toString();
    final userCount = _adminIntValue(group['user_count']);
    setState(() => _mutationPending = true);
    DialogRoute<bool>? dialogRoute;
    try {
      dialogRoute = DialogRoute<bool>(
        context: context,
        builder: (ctx) => ValueListenableBuilder<AppLocale>(
          valueListenable: I18n.localeListenable,
          builder: (ctx, locale, _) => AppDialog(
            title: Text(AdminUiCopy.deleteGroupTitle(name, locale)),
            icon: const Icon(Icons.delete_outline),
            content: Text(AdminUiCopy.deleteGroupBody(userCount, locale)),
            actions: [
              TextButton(
                onPressed: () => _closeDialog(ctx, dialogRoute!, origin, false),
                child: Text(AdminUiCopy.cancelFor(locale)),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                  foregroundColor: Theme.of(ctx).colorScheme.onError,
                ),
                onPressed: () => _closeDialog(ctx, dialogRoute!, origin, true),
                child: Text(AdminUiCopy.deleteFor(locale)),
              ),
            ],
          ),
        ),
      );
      final confirmed = await Navigator.of(context).push(dialogRoute);
      await dialogRoute.completed;
      if (confirmed != true || !origin.isCurrent()) return;
      final result = await AdminApi(
        origin.client,
      ).deleteGroup(id, isCurrent: origin.isCurrent);
      if (!origin.isCurrent()) return;
      final reloaded = await _load(
        origin: _captureRead(),
        mutationOrigin: origin,
        offset: _offsetAfterAdminDelete(
          offset: _offset,
          itemCount: _groups.length,
          pageSize: _pageSize,
        ),
      );
      final reassigned = _adminIntValue(result['reassigned_users']);
      _showSnack(
        origin,
        (locale) => reloaded
            ? AdminUiCopy.groupDeleted(reassigned, locale)
            : AdminUiCopy.groupDeletedRefreshFailedFor(locale),
      );
    } catch (error) {
      _showSnack(
        origin,
        (locale) => _adminActionErrorMessage(
          error,
          AdminUiCopy.actionDeleteGroupFor(locale),
          locale,
        ),
      );
    } finally {
      if (dialogRoute != null) await dialogRoute.completed;
      if (mounted) setState(() => _mutationPending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final readOrigin = _captureRead();
    final writeOrigin = _actionHost.capture(client: widget.api.client);
    final failedLoad = _failedLoad;
    Future<void> retry() async {
      if (!readOrigin.isCurrent()) return;
      if (failedLoad != null) {
        await failedLoad();
      } else {
        await _load(origin: readOrigin);
      }
    }

    final error = _error == null
        ? null
        : _adminErrorMessage(_error!, AdminUiCopy.groupsTarget);
    if (_loading && _groups.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null && _groups.isEmpty) {
      return _AdminErrorState(message: error, onRetry: retry);
    }
    final cs = Theme.of(context).colorScheme;
    final canManageGroups = _canManageGroups;
    final page =
        _page ??
        AdminPage.fromItems(_groups, limit: _pageSize, offset: _offset);
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              await _load(origin: readOrigin, offset: _offset);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                if (error != null)
                  _AdminErrorState(message: error, onRetry: retry),
                if (_loading) const LinearProgressIndicator(),
                _AdminSettingsSection(
                  title: AdminUiCopy.groupManagementTitle,
                  subtitle: AdminUiCopy.groupManagementSubtitle,
                  children: [
                    AppInfoBanner(
                      icon: Icons.toll_outlined,
                      title: AdminUiCopy.groupDefaultQuotaTitle,
                      message: AdminUiCopy.groupDefaultQuotaMessage,
                      color: cs.primary,
                      margin: EdgeInsets.zero,
                    ),
                    if (canManageGroups) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton.icon(
                          onPressed: _mutationPending
                              ? null
                              : () => _editGroup(writeOrigin),
                          icon: const Icon(Icons.add),
                          label: Text(AdminUiCopy.addGroupTitle),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                if (page.items.isEmpty)
                  EmptyState(
                    icon: Icons.groups_2_outlined,
                    message: AdminUiCopy.noGroups,
                  )
                else
                  for (final group in page.items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _AdminGroupSummaryCard(
                        group: group,
                        canManage: canManageGroups && !_mutationPending,
                        showDelete: true,
                        onEdit: () => _editGroup(writeOrigin, group),
                        onDelete: () => _deleteGroup(writeOrigin, group),
                      ),
                    ),
              ],
            ),
          ),
        ),
        _AdminPaginationBar(
          barKey: const ValueKey('admin_groups_pagination_bar'),
          page: page,
          loading: _loading,
          pageSize: _pageSize,
          onPrevious: () => _load(
            origin: readOrigin,
            offset: _previousAdminOffset(_offset, _pageSize),
          ),
          onNext: () => _load(origin: readOrigin, offset: _offset + _pageSize),
          onJumpToPage: (pageNo) => _load(
            origin: readOrigin,
            offset: ((pageNo - 1) * _pageSize).clamp(0, page.total),
          ),
          onPageSizeChanged: (value) =>
              _load(origin: readOrigin, pageSize: value, offset: 0),
        ),
      ],
    );
  }
}

// ====================================================================
// 全站设置
// ====================================================================

class _SettingsTab extends StatefulWidget {
  final AdminApi api;
  final List<String>? selfAdminPermissions;

  const _SettingsTab({
    super.key,
    required this.api,
    required this.selfAdminPermissions,
  });
  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  Map<String, dynamic> _data = {};
  List<Map<String, dynamic>> _groups = [];
  List<Map<String, dynamic>> _roles = [];
  bool _loading = true;
  final Set<String> _savingKeys = <String>{};
  Object? _errorObject;
  Object? _groupsErrorObject;
  Object? _rolesErrorObject;
  final _msgCtrl = TextEditingController();
  final _latestVersionCtrl = TextEditingController();
  final _minimumVersionCtrl = TextEditingController();
  final _defaultCoinsCtrl = TextEditingController(text: '100');
  String _updateVersionPreset = _adminUpdatePresetCurrent;

  bool _canUseAdminPermission(String permission) {
    final permissions = widget.selfAdminPermissions;
    if (permissions == null) return true;
    return permissions.contains(_adminAllPermission) ||
        permissions.contains(permission);
  }

  bool get _canManageGroups => _canUseAdminPermission('groups');
  bool get _canManageRoles => _canUseAdminPermission('roles');

  String? get _error {
    final err = _errorObject;
    if (err == null) return null;
    return _adminErrorMessage(err, AdminUiCopy.settingsTarget);
  }

  String? get _groupsRolesError {
    final ge = _groupsErrorObject;
    final re = _rolesErrorObject;
    if (ge == null && re == null) return null;
    final parts = <String>[];
    if (ge != null) parts.add(_adminErrorMessage(ge, AdminUiCopy.groupsTarget));
    if (re != null) parts.add(_adminErrorMessage(re, AdminUiCopy.rolesTarget));
    return parts.join('\n');
  }

  @override
  void initState() {
    super.initState();
    I18n.localeListenable.addListener(_handleLocaleChanged);
    _load();
  }

  @override
  void dispose() {
    I18n.localeListenable.removeListener(_handleLocaleChanged);
    _msgCtrl.dispose();
    _latestVersionCtrl.dispose();
    _minimumVersionCtrl.dispose();
    _defaultCoinsCtrl.dispose();
    super.dispose();
  }

  void _handleLocaleChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorObject = null;
      _groupsErrorObject = null;
      _rolesErrorObject = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        widget.api.getSettings(),
        _loadGroupsForSettings(),
        _loadRolesForSettings(),
      ]);
      final data = results[0] as Map<String, dynamic>;
      if (!mounted) return;
      _data = data;
      _groups = List<Map<String, dynamic>>.from(results[1] as List);
      _roles = List<Map<String, dynamic>>.from(results[2] as List);
      _msgCtrl.text = (_data['maintenance_message'] ?? '').toString();
      _defaultCoinsCtrl.text = (_data['default_registration_coins'] ?? 100)
          .toString();
      final latestVersion = (_data['latest_version'] ?? '').toString().trim();
      final minimumVersion = (_data['minimum_supported_version'] ?? '')
          .toString()
          .trim();
      _latestVersionCtrl.text = latestVersion.isEmpty
          ? _serverCurrentVersion
          : latestVersion;
      _minimumVersionCtrl.text = minimumVersion.isEmpty
          ? _serverCurrentVersion
          : minimumVersion;
      _updateVersionPreset = _presetForVersions(
        latestVersion: _latestVersionCtrl.text,
        minimumSupportedVersion: _minimumVersionCtrl.text,
      );
    } catch (e) {
      if (!mounted) return;
      _errorObject = e;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _set(String key, dynamic value) async {
    if (_saving(key)) return;
    if (key == 'force_update_required') {
      await _saveForceUpdateRequired(value == true);
      return;
    }
    setState(() => _savingKeys.add(key));
    try {
      await widget.api.updateSettings(
        inviteCodeRequired: key == 'invite_code_required' ? value : null,
        registrationEnabled: key == 'registration_enabled' ? value : null,
        registrationEmailRequired: key == 'registration_email_required'
            ? value
            : null,
        maintenanceMode: key == 'maintenance_mode' ? value : null,
        maintenanceMessage: key == 'maintenance_message' ? value : null,
        forceUpdateRequired: key == 'force_update_required' ? value : null,
        latestVersion: key == 'latest_version' ? value : null,
        minimumSupportedVersion: key == 'minimum_supported_version'
            ? value
            : null,
        updateNotes: key == 'update_notes' ? value : null,
        updateDownloadUrl: key == 'update_download_url' ? value : null,
        defaultRegistrationCoins: key == 'default_registration_coins'
            ? (value is int ? value : int.tryParse(value.toString()) ?? 100)
            : null,
      );
      if (!mounted) return;
      _data[key] = value;
      _showSettingsSnack(() => AdminUiCopy.settingsUpdated);
    } on ApiException catch (e) {
      if (mounted) {
        _showSettingsSnack(() => userVisibleApiError(e));
      }
    } catch (e) {
      if (mounted) {
        _showSettingsSnack(
          () => _adminActionErrorMessage(e, AdminUiCopy.actionUpdateSettings),
        );
      }
    } finally {
      if (mounted) setState(() => _savingKeys.remove(key));
    }
  }

  bool _saving(String key) => _savingKeys.contains(key);

  Future<void> _reloadGroupsRoles() async {
    _groupsErrorObject = null;
    _rolesErrorObject = null;
    final results = await Future.wait<dynamic>([
      _loadGroupsForSettings(),
      _loadRolesForSettings(),
    ]);
    if (!mounted) return;
    setState(() {
      _groups = List<Map<String, dynamic>>.from(results[0] as List);
      _roles = List<Map<String, dynamic>>.from(results[1] as List);
    });
  }

  Future<List<Map<String, dynamic>>> _loadGroupsForSettings() async {
    try {
      return await widget.api.listGroups();
    } catch (error) {
      _groupsErrorObject = error;
      return const <Map<String, dynamic>>[];
    }
  }

  Future<List<Map<String, dynamic>>> _loadRolesForSettings() async {
    try {
      return await widget.api.listRoles();
    } catch (error) {
      _rolesErrorObject = error;
      return const <Map<String, dynamic>>[];
    }
  }

  Future<void> _editGroup([Map<String, dynamic>? group]) async {
    if (!_canManageGroups) {
      _showSettingsSnack(() => AdminUiCopy.missingGroupsPermission);
      return;
    }
    final nameCtrl = TextEditingController(
      text: (group?['name'] ?? '').toString(),
    );
    final descCtrl = TextEditingController(
      text: (group?['description'] ?? '').toString(),
    );
    final coinsCtrl = TextEditingController(
      text: _adminIntValueOrDefault(
        group?['default_time_coins'],
        100,
      ).toString(),
    );
    var isActive = group?['is_active'] != false;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => ValueListenableBuilder<AppLocale>(
          valueListenable: I18n.localeListenable,
          builder: (ctx, locale, _) => AppDialog(
            title: Text(
              group == null
                  ? AdminUiCopy.addGroupTitleFor(locale)
                  : AdminUiCopy.editGroupTitleFor(locale),
            ),
            icon: const Icon(Icons.groups_2_outlined),
            content: _adminDialogForm(
              maxWidth: 430,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: AdminUiCopy.groupNameLabelFor(locale),
                  ),
                  textInputAction: TextInputAction.next,
                ),
                TextField(
                  controller: descCtrl,
                  decoration: InputDecoration(
                    labelText: AdminUiCopy.groupDescriptionLabelFor(locale),
                    helperText: AdminUiCopy.groupDescriptionHelperFor(locale),
                  ),
                  maxLines: 2,
                ),
                TextField(
                  controller: coinsCtrl,
                  decoration: InputDecoration(
                    labelText: AdminUiCopy.groupDefaultCoinsLabelFor(locale),
                    helperText: AdminUiCopy.groupDefaultCoinsHelperFor(locale),
                    prefixIcon: const Icon(Icons.toll_outlined),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: isActive,
                  title: Text(AdminUiCopy.groupEnableLabelFor(locale)),
                  subtitle: Text(AdminUiCopy.groupEnableSubtitleFor(locale)),
                  onChanged: (value) => setSt(() => isActive = value),
                ),
              ],
            ),
            actions: _adminDialogActions(ctx, locale: locale),
          ),
        ),
      ),
    );
    if (saved != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) {
      _showSettingsSnack(() => AdminUiCopy.pleaseEnterGroupName);
      return;
    }
    try {
      await widget.api.saveGroup(
        id: group?['id']?.toString(),
        name: name,
        description: descCtrl.text.trim(),
        defaultTimeCoins: (int.tryParse(coinsCtrl.text.trim()) ?? 100).clamp(
          0,
          1000000,
        ),
        isActive: isActive,
      );
      if (!mounted) return;
      await _reloadGroupsRoles();
      _showSettingsSnack(() => AdminUiCopy.groupSaved);
    } on ApiException catch (e) {
      _showSettingsSnack(() => userVisibleApiError(e));
    } catch (e) {
      _showSettingsSnack(
        () => _adminActionErrorMessage(e, AdminUiCopy.actionSaveGroup),
      );
    }
  }

  Future<void> _editRole([Map<String, dynamic>? role]) async {
    if (!_canManageRoles) {
      _showSettingsSnack(() => AdminUiCopy.missingRolesPermission);
      return;
    }
    final nameCtrl = TextEditingController(
      text: (role?['name'] ?? '').toString(),
    );
    final descCtrl = TextEditingController(
      text: (role?['description'] ?? '').toString(),
    );
    final rawPermissions = role?['permission_codes'] ?? role?['permissions'];
    var selected = _adminUserPermissions(rawPermissions, isAdmin: true).toSet();
    if (selected.contains(_adminAllPermission)) {
      selected = _adminAllPermissionKeys();
    }
    var isActive = role?['is_active'] != false;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => ValueListenableBuilder<AppLocale>(
          valueListenable: I18n.localeListenable,
          builder: (ctx, locale, _) => AppDialog(
            title: Text(
              role == null
                  ? AdminUiCopy.addRoleTitleFor(locale)
                  : AdminUiCopy.editRoleTitleFor(locale),
            ),
            icon: const Icon(Icons.admin_panel_settings_outlined),
            content: _adminDialogForm(
              maxWidth: 520,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: AdminUiCopy.roleNameLabelFor(locale),
                  ),
                  textInputAction: TextInputAction.next,
                ),
                TextField(
                  controller: descCtrl,
                  decoration: InputDecoration(
                    labelText: AdminUiCopy.roleDescriptionLabelFor(locale),
                    helperText: AdminUiCopy.roleDescriptionHelperFor(locale),
                  ),
                  maxLines: 2,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: isActive,
                  title: Text(AdminUiCopy.roleEnableLabelFor(locale)),
                  subtitle: Text(AdminUiCopy.roleEnableSubtitleFor(locale)),
                  onChanged: (value) => setSt(() => isActive = value),
                ),
                _adminPermissionChecklist(
                  selected: selected,
                  onChanged: (next) => setSt(() => selected = next),
                  locale: locale,
                ),
              ],
            ),
            actions: _adminDialogActions(ctx, locale: locale),
          ),
        ),
      ),
    );
    if (saved != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) {
      _showSettingsSnack(() => AdminUiCopy.pleaseEnterRoleName);
      return;
    }
    try {
      await widget.api.saveRole(
        id: role?['id']?.toString(),
        name: name,
        description: descCtrl.text.trim(),
        permissions: selected.toList(),
        isActive: isActive,
      );
      if (!mounted) return;
      await _reloadGroupsRoles();
      _showSettingsSnack(() => AdminUiCopy.roleSaved);
    } on ApiException catch (e) {
      _showSettingsSnack(() => userVisibleApiError(e));
    } catch (e) {
      _showSettingsSnack(
        () => _adminActionErrorMessage(e, AdminUiCopy.actionSaveRole),
      );
    }
  }

  bool get _savingUpdateConfig => _savingKeys.any(
    const {
      'latest_version',
      'minimum_supported_version',
      'update_notes',
      'force_update_required',
    }.contains,
  );

  void _showSettingsSnack(ValueGetter<String> message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: _AdminFeedbackText((_) => message())));
  }

  String get _serverCurrentVersion {
    final value =
        (_data['current_version'] ?? _data['current_version_name'] ?? '')
            .toString()
            .trim();
    return value.isEmpty ? AppVersion.name : value;
  }

  String get _nextPatchVersion {
    final parts = _normalizedVersionParts(_serverCurrentVersion);
    return '${parts[0]}.${parts[1]}.${parts[2] + 1}';
  }

  String get _nextMinorVersion {
    final parts = _normalizedVersionParts(_serverCurrentVersion);
    return '${parts[0]}.${parts[1] + 1}.0';
  }

  String get _nextPatchMinimumVersion => _nextPatchVersion;

  List<_AdminUpdateVersionOption> get _updateVersionOptions {
    final raw = _data['version_options'];
    final options = <_AdminUpdateVersionOption>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is! Map) continue;
        final key = (item['key'] ?? '').toString().trim();
        final label = (item['label'] ?? '').toString().trim();
        final latest = (item['latest_version'] ?? '').toString().trim();
        final minimum = (item['minimum_supported_version'] ?? '')
            .toString()
            .trim();
        if (key.isEmpty || latest.isEmpty || minimum.isEmpty) continue;
        if (options.any((option) => option.key == key)) continue;
        options.add(
          _AdminUpdateVersionOption(
            key: key,
            label: label.isEmpty ? key : label,
            latestVersion: latest,
            minimumSupportedVersion: minimum,
          ),
        );
      }
    }
    final fallbackOptions = [
      _AdminUpdateVersionOption(
        key: _adminUpdatePresetCurrent,
        label: AdminUiCopy.versionPresetCurrent,
        latestVersion: _serverCurrentVersion,
        minimumSupportedVersion: _serverCurrentVersion,
      ),
      _AdminUpdateVersionOption(
        key: _adminUpdatePresetNextPatch,
        label: AdminUiCopy.versionPresetNextPatch,
        latestVersion: _nextPatchVersion,
        minimumSupportedVersion: _serverCurrentVersion,
      ),
      _AdminUpdateVersionOption(
        key: _adminUpdatePresetNextMinor,
        label: AdminUiCopy.versionPresetNextMinor,
        latestVersion: _nextMinorVersion,
        minimumSupportedVersion: _serverCurrentVersion,
      ),
      _AdminUpdateVersionOption(
        key: _adminUpdatePresetMinimumNextPatch,
        label: AdminUiCopy.versionPresetMinimumNextPatch,
        latestVersion: _nextPatchVersion,
        minimumSupportedVersion: _nextPatchMinimumVersion,
      ),
    ];
    if (options.isNotEmpty) {
      for (final fallback in fallbackOptions) {
        if (!options.any((option) => option.key == fallback.key)) {
          options.add(fallback);
        }
      }
      return options;
    }
    return fallbackOptions;
  }

  String _latestVersionForSave() {
    return _latestVersionCtrl.text.trim();
  }

  String _minimumSupportedVersionForSave() {
    return _minimumVersionCtrl.text.trim();
  }

  ({String latestVersion, String minimumSupportedVersion, String updateNotes})
  _normalizedUpdateVersionsForSave({
    required bool forceUpdateRequired,
    required String latestVersion,
    required String minimumSupportedVersion,
  }) {
    final latest = latestVersion.trim();
    final minimum = minimumSupportedVersion.trim();
    final current = _serverCurrentVersion;
    final isDefaultCurrentVersions = latest == current && minimum == current;
    final hasExplicitPolicy =
        forceUpdateRequired ||
        _compareAppVersions(latest, current) > 0 ||
        _compareAppVersions(minimum, current) > 0;
    if (isDefaultCurrentVersions && !hasExplicitPolicy) {
      return (latestVersion: '', minimumSupportedVersion: '', updateNotes: '');
    }
    return (
      latestVersion: latest,
      minimumSupportedVersion: minimum,
      updateNotes: _defaultUpdateNotesFor(
        latestVersion: latest,
        locale: I18n.current,
      ),
    );
  }

  void _syncUpdateVersionPreset() {
    final preset = _presetForVersions(
      latestVersion: _latestVersionCtrl.text,
      minimumSupportedVersion: _minimumVersionCtrl.text,
    );
    if (_updateVersionPreset != preset) {
      setState(() => _updateVersionPreset = preset);
    }
  }

  List<int> _normalizedVersionParts(String value) {
    final parts = _versionParts(value);
    return [
      parts.isNotEmpty ? parts[0] : 0,
      parts.length > 1 ? parts[1] : 0,
      parts.length > 2 ? parts[2] : 0,
    ];
  }

  String _presetForVersions({
    required String latestVersion,
    required String minimumSupportedVersion,
  }) {
    final latest = latestVersion.trim();
    final minimum = minimumSupportedVersion.trim();
    for (final option in _updateVersionOptions) {
      if (option.latestVersion == latest &&
          option.minimumSupportedVersion == minimum) {
        return option.key;
      }
    }
    return _adminUpdatePresetCurrent;
  }

  void _applyUpdateVersionPreset(String value) {
    setState(() {
      _updateVersionPreset = value;
      _AdminUpdateVersionOption? option;
      for (final item in _updateVersionOptions) {
        if (item.key == value) {
          option = item;
          break;
        }
      }
      if (option != null) {
        _latestVersionCtrl.text = option.latestVersion;
        _minimumVersionCtrl.text = option.minimumSupportedVersion;
        return;
      }
      switch (value) {
        case _adminUpdatePresetCurrent:
          _latestVersionCtrl.text = _serverCurrentVersion;
          _minimumVersionCtrl.text = _serverCurrentVersion;
          break;
        case _adminUpdatePresetNextPatch:
          _latestVersionCtrl.text = _nextPatchVersion;
          _minimumVersionCtrl.text = _serverCurrentVersion;
          break;
        case _adminUpdatePresetNextMinor:
          _latestVersionCtrl.text = _nextMinorVersion;
          _minimumVersionCtrl.text = _serverCurrentVersion;
          break;
        case _adminUpdatePresetMinimumNextPatch:
          _latestVersionCtrl.text = _nextPatchVersion;
          _minimumVersionCtrl.text = _nextPatchMinimumVersion;
          break;
      }
    });
  }

  String _updateVersionOptionLabel(_AdminUpdateVersionOption option) {
    final label = AdminUiCopy.versionOptionLabel(
      option.key,
      fallback: option.label.trim(),
    );
    final latest = option.latestVersion.trim();
    final minimum = option.minimumSupportedVersion.trim();
    if (latest.isEmpty || minimum.isEmpty) {
      return label.isEmpty ? option.key : label;
    }
    if (latest == minimum) return '$label $latest';
    final minPrefix = AdminUiCopy.minimumVersionPrefix;
    return '$label $latest / $minPrefix $minimum';
  }

  Future<void> _saveUpdateConfig() async {
    if (_savingUpdateConfig) return;
    final latestVersion = _latestVersionForSave();
    final minimumSupportedVersion = _minimumSupportedVersionForSave();
    final forceUpdateRequired = _data['force_update_required'] == true;
    final versions = _normalizedUpdateVersionsForSave(
      forceUpdateRequired: forceUpdateRequired,
      latestVersion: latestVersion,
      minimumSupportedVersion: minimumSupportedVersion,
    );
    final message = _validateUpdatePolicy(
      forceUpdateRequired: forceUpdateRequired,
      latestVersion: latestVersion,
      minimumSupportedVersion: minimumSupportedVersion,
    );
    if (message != null) {
      _showSettingsSnack(
        () =>
            _validateUpdatePolicy(
              forceUpdateRequired: forceUpdateRequired,
              latestVersion: latestVersion,
              minimumSupportedVersion: minimumSupportedVersion,
            ) ??
            message,
      );
      return;
    }

    const keys = {
      'latest_version',
      'minimum_supported_version',
      'update_notes',
      'update_download_url',
    };
    setState(() => _savingKeys.addAll(keys));
    try {
      await widget.api.updateSettings(
        latestVersion: versions.latestVersion,
        minimumSupportedVersion: versions.minimumSupportedVersion,
        updateNotes: versions.updateNotes,
        updateDownloadUrl: '',
      );
      if (!mounted) return;
      _data['latest_version'] = versions.latestVersion;
      _data['minimum_supported_version'] = versions.minimumSupportedVersion;
      _data['update_notes'] = versions.updateNotes;
      _data['update_download_url'] = '';
      _syncUpdateVersionPreset();
      _showSettingsSnack(() => AdminUiCopy.updateConfigSaved);
    } on ApiException catch (e) {
      _showSettingsSnack(() => userVisibleApiError(e));
    } catch (e) {
      _showSettingsSnack(
        () => _adminActionErrorMessage(e, AdminUiCopy.actionSaveUpdateConfig),
      );
    } finally {
      if (mounted) setState(() => _savingKeys.removeAll(keys));
    }
  }

  Future<void> _saveForceUpdateRequired(bool value) async {
    if (_savingUpdateConfig) return;
    final latestVersion = _latestVersionForSave();
    final minimumSupportedVersion = _minimumSupportedVersionForSave();
    final versions = _normalizedUpdateVersionsForSave(
      forceUpdateRequired: value,
      latestVersion: latestVersion,
      minimumSupportedVersion: minimumSupportedVersion,
    );
    final message = _validateUpdatePolicy(
      forceUpdateRequired: value,
      latestVersion: latestVersion,
      minimumSupportedVersion: minimumSupportedVersion,
    );
    if (message != null) {
      _showSettingsSnack(
        () =>
            _validateUpdatePolicy(
              forceUpdateRequired: value,
              latestVersion: latestVersion,
              minimumSupportedVersion: minimumSupportedVersion,
            ) ??
            message,
      );
      return;
    }

    const keys = {
      'force_update_required',
      'latest_version',
      'minimum_supported_version',
      'update_notes',
      'update_download_url',
    };
    setState(() => _savingKeys.addAll(keys));
    try {
      await widget.api.updateSettings(
        forceUpdateRequired: value,
        latestVersion: versions.latestVersion,
        minimumSupportedVersion: versions.minimumSupportedVersion,
        updateNotes: versions.updateNotes,
        updateDownloadUrl: '',
      );
      if (!mounted) return;
      _data['force_update_required'] = value;
      _data['latest_version'] = versions.latestVersion;
      _data['minimum_supported_version'] = versions.minimumSupportedVersion;
      _data['update_notes'] = versions.updateNotes;
      _data['update_download_url'] = '';
      _syncUpdateVersionPreset();
      _showSettingsSnack(() => AdminUiCopy.settingsUpdated);
    } on ApiException catch (e) {
      _showSettingsSnack(() => userVisibleApiError(e));
    } catch (e) {
      _showSettingsSnack(
        () => _adminActionErrorMessage(e, AdminUiCopy.actionUpdateForceUpdate),
      );
    } finally {
      if (mounted) setState(() => _savingKeys.removeAll(keys));
    }
  }

  String? _validateUpdatePolicy({
    required bool forceUpdateRequired,
    required String latestVersion,
    required String minimumSupportedVersion,
  }) {
    final hasAnyUpdatePolicy =
        forceUpdateRequired ||
        _compareAppVersions(latestVersion, _serverCurrentVersion) > 0 ||
        _compareAppVersions(minimumSupportedVersion, _serverCurrentVersion) > 0;
    if (!hasAnyUpdatePolicy) return null;
    return null;
  }

  String _defaultUpdateNotesFor({
    required String latestVersion,
    AppLocale? locale,
  }) {
    final target = latestVersion.trim().isEmpty
        ? _serverCurrentVersion
        : latestVersion;
    return AdminUiCopy.defaultUpdateNotes(target, locale: locale);
  }

  String _updateNotesPreview([AppLocale? locale]) {
    final existing = (_data['update_notes'] ?? '').toString().trim();
    if (_updateVersionPreset == _adminUpdatePresetCurrent &&
        existing.isNotEmpty) {
      return existing;
    }
    return _defaultUpdateNotesFor(
      latestVersion: _latestVersionForSave(),
      locale: locale,
    );
  }

  Widget _groupRoleManagementSection(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final locale = I18n.current;
    final canManageGroups = _canManageGroups;
    final canManageRoles = _canManageRoles;
    final surfaceStyle = appSurfaceStyleOf(context);
    final cardFill = surfaceStyle?.cardFillColor ?? cs.surface;
    final cardBackground = Color.alphaBlend(
      cardFill,
      theme.scaffoldBackgroundColor,
    );
    final textButtonForeground = surfaceStyle != null
        ? appReadableForeground(cardBackground, cs.primary)
        : cs.primary;
    final groupCards = _groups.take(6).map((group) {
      return _AdminGroupSummaryCard(
        group: group,
        canManage: canManageGroups,
        onEdit: () => _editGroup(group),
      );
    }).toList();
    final roleCards = _roles.take(6).map((role) {
      final active = role['is_active'] != false;
      final name = (role['name'] ?? role['id'] ?? '').toString();
      final userCount = _adminIntValue(role['user_count']);
      final permissions = _adminUserPermissions(
        role['permission_codes'] ?? role['permissions'],
        isAdmin: true,
      );
      return _AdminListTileCard(
        dense: true,
        leading: Icon(
          Icons.admin_panel_settings_outlined,
          color: active ? Colors.indigo : cs.onSurfaceVariant,
        ),
        title: Text(name.isEmpty ? AdminUiCopy.unnamedRoleFor(locale) : name),
        subtitle: Text(
          '${_adminPermissionsLabel(permissions, isAdmin: true, locale: locale)} · ${AdminUiCopy.userCountLabel(userCount, locale)} · ${active ? AdminUiCopy.enabledFor(locale) : AdminUiCopy.disabledFor(locale)}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: canManageRoles
            ? IconButton(
                tooltip: AdminUiCopy.editRoleTooltipFor(locale),
                onPressed: () => _editRole(role),
                icon: const Icon(Icons.edit_outlined),
              )
            : null,
      );
    }).toList();

    return _AdminSettingsSection(
      title: AdminUiCopy.groupsAndRolesTitleFor(locale),
      subtitle: AdminUiCopy.groupsAndRolesSubtitleFor(locale),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final inheritedStyle = Theme.of(context).textButtonTheme.style;
            final actionButtonStyle = surfaceStyle != null
                ? (inheritedStyle ?? const ButtonStyle()).copyWith(
                    foregroundColor: WidgetStatePropertyAll(
                      textButtonForeground,
                    ),
                    iconColor: WidgetStatePropertyAll(textButtonForeground),
                    textStyle: WidgetStatePropertyAll(
                      appSecondaryControlTextStyle(context).copyWith(
                        color: textButtonForeground,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                    minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
                  )
                : null;
            final summary = Text(
              AdminUiCopy.groupsRolesSummary(
                _groups.length,
                _roles.length,
                locale,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurface.withValues(alpha: 0.62),
              ),
            );
            final actions = <Widget>[
              if (canManageGroups)
                TextButton.icon(
                  style: actionButtonStyle,
                  onPressed: () => _editGroup(),
                  icon: const Icon(Icons.add),
                  label: Text(AdminUiCopy.addGroupBtnFor(locale)),
                ),
              if (canManageRoles)
                TextButton.icon(
                  style: actionButtonStyle,
                  onPressed: () => _editRole(),
                  icon: const Icon(Icons.add),
                  label: Text(AdminUiCopy.addRoleBtnFor(locale)),
                ),
            ];
            final actionWrap = Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: actions,
            );
            if (constraints.maxWidth < 420) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  summary,
                  if (actions.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    actionWrap,
                  ],
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: summary),
                if (actions.isNotEmpty) actionWrap,
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        if (_groupsRolesError != null) ...[
          AppInfoBanner(
            icon: Icons.lock_outline,
            title: AdminUiCopy.groupsRolesLoadFailedFor(locale),
            message: _groupsRolesError!,
            color: cs.error,
            margin: EdgeInsets.zero,
          ),
          const SizedBox(height: 8),
        ],
        if (_groups.isEmpty)
          AppInfoBanner(
            icon: Icons.groups_2_outlined,
            title: AdminUiCopy.noManageableGroupsFor(locale),
            message: _groupsRolesError == null
                ? AdminUiCopy.emptyBackendReturnFor(locale)
                : AdminUiCopy.errorAboveExplainsWhyFor(locale),
            color: Colors.blueGrey,
            margin: EdgeInsets.zero,
          )
        else
          ...groupCards,
        const SizedBox(height: 8),
        if (_roles.isEmpty)
          AppInfoBanner(
            icon: Icons.admin_panel_settings_outlined,
            title: AdminUiCopy.noManageableRolesFor(locale),
            message: _groupsRolesError == null
                ? AdminUiCopy.emptyBackendReturnFor(locale)
                : AdminUiCopy.errorAboveExplainsWhyFor(locale),
            color: Colors.blueGrey,
            margin: EdgeInsets.zero,
          )
        else
          ...roleCards,
      ],
    );
  }

  int _compareAppVersions(String a, String b) {
    final pa = _versionParts(a);
    final pb = _versionParts(b);
    for (var i = 0; i < 3; i++) {
      final ai = i < pa.length ? pa[i] : 0;
      final bi = i < pb.length ? pb[i] : 0;
      if (ai != bi) return ai.compareTo(bi);
    }
    return 0;
  }

  List<int> _versionParts(String value) {
    return value
        .trim()
        .replaceFirst(RegExp(r'^v'), '')
        .split('-')
        .first
        .split('+')
        .first
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _AdminErrorState(message: _error!, onRetry: _load);
    }
    final cs = Theme.of(context).colorScheme;
    final locale = I18n.current;

    return AppSecondaryControlTheme(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _AdminSettingsSection(
            title: AdminUiCopy.accountsRegistrationSectionTitleFor(locale),
            subtitle: AdminUiCopy.accountsRegistrationSectionSubtitleFor(
              locale,
            ),
            children: [
              AppSwitchTile(
                icon: Icons.person_add_alt_1_outlined,
                color: Colors.green,
                value: _data['registration_enabled'] == true,
                title: AdminUiCopy.registrationEnabledTitleFor(locale),
                subtitle: AdminUiCopy.registrationEnabledSubtitleFor(locale),
                onChanged: _saving('registration_enabled')
                    ? null
                    : (v) => _set('registration_enabled', v),
              ),
              AppSwitchTile(
                icon: Icons.vpn_key_outlined,
                color: Colors.purple,
                value: _data['invite_code_required'] == true,
                title: AdminUiCopy.inviteCodeRequiredTitleFor(locale),
                subtitle: AdminUiCopy.inviteCodeRequiredSubtitleFor(locale),
                onChanged: _saving('invite_code_required')
                    ? null
                    : (v) => _set('invite_code_required', v),
              ),
              AppSwitchTile(
                icon: Icons.mark_email_read_outlined,
                color: Colors.teal,
                value: _data['registration_email_required'] == true,
                title: AdminUiCopy.registrationEmailRequiredTitleFor(locale),
                subtitle: AdminUiCopy.registrationEmailRequiredSubtitleFor(
                  locale,
                ),
                onChanged: _saving('registration_email_required')
                    ? null
                    : (v) => _set('registration_email_required', v),
              ),
              const SizedBox(height: 10),
              _AdminSettingsTextField(
                controller: _defaultCoinsCtrl,
                label: AdminUiCopy.defaultCoinsLabelFor(locale),
                enabled: !_saving('default_registration_coins'),
                decoration: InputDecoration(
                  helperText: AdminUiCopy.defaultCoinsHelperFor(locale),
                  prefixIcon: const Icon(Icons.toll_outlined),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onEditingComplete: () {
                  final coins =
                      int.tryParse(_defaultCoinsCtrl.text.trim()) ?? 100;
                  _set('default_registration_coins', coins.clamp(0, 1000000));
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          _groupRoleManagementSection(context),
          const SizedBox(height: 12),
          _AdminSettingsSection(
            title: AdminUiCopy.maintenanceSectionTitleFor(locale),
            subtitle: AdminUiCopy.maintenanceSectionSubtitleFor(locale),
            children: [
              AppSwitchTile(
                icon: Icons.construction_outlined,
                color: Colors.orange,
                value: _data['maintenance_mode'] == true,
                title: AdminUiCopy.maintenanceModeTitleFor(locale),
                subtitle: AdminUiCopy.maintenanceModeSubtitleFor(locale),
                onChanged: _saving('maintenance_mode')
                    ? null
                    : (v) => _set('maintenance_mode', v),
              ),
              const SizedBox(height: 10),
              _AdminSettingsTextField(
                controller: _msgCtrl,
                label: AdminUiCopy.maintenanceMessageLabelFor(locale),
                enabled: !_saving('maintenance_message'),
                decoration: InputDecoration(
                  hintText: AdminUiCopy.maintenanceMessageHintFor(locale),
                  prefixIcon: const Icon(Icons.campaign_outlined),
                ),
                onEditingComplete: () =>
                    _set('maintenance_message', _msgCtrl.text.trim()),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _AdminSettingsSection(
            title: AdminUiCopy.appUpdateSectionTitleFor(locale),
            subtitle: AdminUiCopy.appUpdateSectionSubtitleFor(locale),
            children: [
              AppSwitchTile(
                icon: Icons.system_update_alt_outlined,
                color: cs.error,
                value: _data['force_update_required'] == true,
                title: AdminUiCopy.forceUpdateTitleFor(locale),
                subtitle: AdminUiCopy.forceUpdateSubtitleFor(locale),
                onChanged: _savingUpdateConfig
                    ? null
                    : (v) => _set('force_update_required', v),
              ),
              const SizedBox(height: 10),
              AppInfoBanner(
                icon: Icons.info_outline,
                title: AdminUiCopy.currentClientVersionTitle(
                  AppVersion.name,
                  locale,
                ),
                message: AdminUiCopy.currentClientVersionMessageFor(locale),
                color: Theme.of(context).colorScheme.primary,
                margin: EdgeInsets.zero,
              ),
              const SizedBox(height: 10),
              AppDropdownField<String>(
                key: ValueKey(_updateVersionPreset),
                enabled: !_savingUpdateConfig,
                initialValue: _updateVersionPreset,
                labelText: AdminUiCopy.versionPolicyLabelFor(locale),
                prefixIcon: const Icon(Icons.rule_folder_outlined),
                items: [
                  for (final option in _updateVersionOptions)
                    DropdownMenuItem(
                      value: option.key,
                      child: Text(_updateVersionOptionLabel(option)),
                    ),
                ],
                onChanged: (value) {
                  if (_savingUpdateConfig) return;
                  if (value != null) _applyUpdateVersionPreset(value);
                },
              ),
              const SizedBox(height: 10),
              AppInfoBanner(
                icon: Icons.new_releases_outlined,
                title: AdminUiCopy.versionSelectionTitleFor(locale),
                message: AdminUiCopy.versionSelectionMessage(
                  _latestVersionForSave(),
                  _minimumSupportedVersionForSave(),
                  locale,
                ),
                color: Colors.teal,
                margin: EdgeInsets.zero,
              ),
              const SizedBox(height: 10),
              AppInfoBanner(
                icon: Icons.notes_outlined,
                title: AdminUiCopy.updateNotesPreviewTitleFor(locale),
                message: _updateNotesPreview(locale),
                color: Colors.blueGrey,
                margin: EdgeInsets.zero,
              ),
              const SizedBox(height: 6),
              Text(
                AdminUiCopy.updateNotesSaveHintFor(locale),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurface.withValues(alpha: 0.62),
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _savingUpdateConfig ? null : _saveUpdateConfig,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(AdminUiCopy.saveUpdateConfigBtnFor(locale)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AppInfoBanner(
            icon: Icons.info_outline,
            color: cs.primary,
            title: AdminUiCopy.serverAddressTitleFor(locale),
            message: AdminUiCopy.serverAddressMessageFor(locale),
          ),
        ],
      ),
    );
  }
}

// ====================================================================
// AI 配置
// ====================================================================

class _AiSettingsTab extends StatefulWidget {
  final AdminApi api;
  const _AiSettingsTab({super.key, required this.api});
  @override
  State<_AiSettingsTab> createState() => _AiSettingsTabState();
}

class _AiTestResultData {
  final bool skipped;
  final bool enabled;
  final String model;
  final String sample;
  final String message;
  final Object? error;

  const _AiTestResultData({
    this.skipped = false,
    this.enabled = true,
    this.model = '',
    this.sample = '',
    this.message = '',
    this.error,
  });

  String format(AppLocale locale) {
    if (error != null) {
      return _adminAiFailureReason(error!, locale);
    }
    if (skipped) {
      return message.isNotEmpty
          ? message
          : AdminUiCopy.aiTestSkippedMessage(model, locale: locale);
    }
    if (enabled) {
      return AdminUiCopy.aiTestSuccessMessage(model, sample, locale: locale);
    }
    return AdminUiCopy.aiTestDisabledMessage(model, locale: locale);
  }
}

class _AiSettingsTabState extends State<_AiSettingsTab> {
  bool _loading = true;
  bool _saving = false;
  bool _testing = false;
  _AiTestResultData? _testResultData;
  Color _testColor = Colors.grey;
  Object? _errorObject;
  bool _enabled = false;
  final _baseCtrl = TextEditingController();
  final _baseFocusNode = FocusNode();
  final _keyCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _quotaCtrl = TextEditingController(text: '0');
  bool _keyMasked = true;

  @override
  void initState() {
    super.initState();
    I18n.localeListenable.addListener(_onLocaleChanged);
    _load();
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    I18n.localeListenable.removeListener(_onLocaleChanged);
    _baseCtrl.dispose();
    _baseFocusNode.dispose();
    _keyCtrl.dispose();
    _modelCtrl.dispose();
    _quotaCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorObject = null;
    });
    try {
      final data = await widget.api.getSettings(scope: 'ai');
      if (!mounted) return;
      _enabled = data['ai_enabled'] == true;
      _baseCtrl.text = (data['ai_base_url'] ?? '').toString();
      _keyCtrl.text = (data['ai_api_key'] ?? '').toString();
      _keyMasked = (data['ai_api_key_set'] == true);
      _modelCtrl.text = (data['ai_model'] ?? '').toString();
      _quotaCtrl.text = (((data['ai_daily_quota'] as num?) ?? 0).toInt())
          .toString();
      context.read<AiService>().updateFromServerConfig(data);
    } catch (e) {
      if (!mounted) return;
      _errorObject = e;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final newKey = _keyCtrl.text.trim();
      final submitKey = (_keyMasked && newKey.contains('***')) ? null : newKey;
      final payload = <String, Object?>{
        'ai_enabled': _enabled,
        'ai_base_url': _baseCtrl.text.trim(),
        'ai_model': _modelCtrl.text.trim(),
        'ai_daily_quota': int.tryParse(_quotaCtrl.text.trim()) ?? 0,
      };
      if (submitKey != null) {
        payload['ai_api_key'] = submitKey;
      }
      await widget.api.client.patch('/api/admin/settings', payload);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: _AdminFeedbackText(
            (locale) => AdminUiCopy.aiConfigSavedFor(locale),
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: _AdminFeedbackText(
              (locale) => _adminActionErrorMessage(
                e,
                AdminUiCopy.actionSaveAiConfigFor(locale),
                locale,
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _test() async {
    if (_testing) return;
    setState(() {
      _testing = true;
      _testResultData = null;
    });
    try {
      final newKey = _keyCtrl.text.trim();
      final submitKey = (_keyMasked && newKey.contains('***')) ? null : newKey;
      final res = await widget.api.testAi(
        aiEnabled: _enabled,
        baseUrl: _baseCtrl.text.trim(),
        apiKey: submitKey,
        model: _modelCtrl.text.trim(),
      );
      if (!mounted) return;
      final model = (res['model'] ?? _modelCtrl.text.trim()).toString().trim();
      final sample = (res['sample'] ?? '').toString().trim();
      final enabled = res['enabled'] != false;
      final skipped = res['skipped'] == true;
      final message = (res['message'] ?? '').toString().trim();
      setState(() {
        _testResultData = _AiTestResultData(
          skipped: skipped,
          enabled: enabled,
          model: model,
          sample: sample,
          message: message,
        );
        _testColor = skipped ? Colors.orange : Colors.green;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _testResultData = _AiTestResultData(error: e);
        _testColor = Theme.of(context).colorScheme.error;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testResultData = _AiTestResultData(error: e);
        _testColor = Theme.of(context).colorScheme.error;
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = I18n.current;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_errorObject != null) {
      return _AdminErrorState(
        message: _adminErrorMessage(
          _errorObject!,
          AdminUiCopy.aiSettingsTabTitleFor(locale),
          locale,
        ),
        onRetry: _load,
      );
    }
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final media = MediaQuery.of(context);
    final isCompactOrScaled =
        media.size.width < 360 || media.textScaler.scale(1.0) > 1.25;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _AdminSettingsSection(
          title: AdminUiCopy.aiSectionTitleFor(locale),
          subtitle: AdminUiCopy.aiSectionSubtitleFor(locale),
          children: [
            AppSwitchTile(
              icon: Icons.auto_awesome,
              color: cs.primary,
              value: _enabled,
              title: AdminUiCopy.aiEnableTitleFor(locale),
              subtitle: AdminUiCopy.aiEnableSubtitleFor(locale),
              onChanged: (v) => setState(() => _enabled = v),
            ),
            if (isCompactOrScaled) ...[
              const SizedBox(height: 10),
              ExcludeSemantics(
                child: Text(
                  AdminUiCopy.aiBaseUrlLabelFor(locale),
                  style:
                      (theme.inputDecorationTheme.labelStyle ??
                              theme.textTheme.bodyMedium ??
                              const TextStyle())
                          .copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.normal,
                          ),
                ),
              ),
              const SizedBox(height: 6),
            ] else
              const SizedBox(height: 10),
            Semantics(
              label: isCompactOrScaled
                  ? AdminUiCopy.aiBaseUrlLabelFor(locale)
                  : null,
              child: TextField(
                key: const ValueKey('admin_ai_base_url_field'),
                controller: _baseCtrl,
                focusNode: _baseFocusNode,
                decoration: InputDecoration(
                  labelText: isCompactOrScaled
                      ? null
                      : AdminUiCopy.aiBaseUrlLabelFor(locale),
                  hintText: 'https://api.openai.com',
                  helperText: AdminUiCopy.aiBaseUrlHelperFor(locale),
                  prefixIcon: const Icon(Icons.link_outlined),
                ),
              ),
            ),
            const SizedBox(height: 10),
            _AdminSettingsTextField(
              controller: _keyCtrl,
              label: 'API Key',
              decoration: InputDecoration(
                helperText: _keyMasked
                    ? AdminUiCopy.aiApiKeyConfiguredHelperFor(locale)
                    : AdminUiCopy.aiApiKeyNotConfiguredHelperFor(locale),
                prefixIcon: const Icon(Icons.key_outlined),
              ),
            ),
            const SizedBox(height: 10),
            _AdminSettingsTextField(
              controller: _modelCtrl,
              label: AdminUiCopy.aiModelLabelFor(locale),
              decoration: InputDecoration(
                hintText: 'gpt-4o-mini / claude-3-haiku-20240307',
                prefixIcon: const Icon(Icons.memory_outlined),
              ),
            ),
            const SizedBox(height: 10),
            _AdminSettingsTextField(
              controller: _quotaCtrl,
              label: AdminUiCopy.aiDailyQuotaLabelFor(locale),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                helperText: AdminUiCopy.aiDailyQuotaHelperFor(locale),
                prefixIcon: const Icon(Icons.speed_outlined),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(
                    _saving
                        ? AdminUiCopy.savingEllipsis(locale)
                        : AdminUiCopy.saveBtnFor(locale),
                  ),
                ),
                OutlinedButton.icon(
                  icon: _testing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.network_check),
                  label: Text(AdminUiCopy.aiTestCurrentFormFor(locale)),
                  onPressed: _testing ? null : _test,
                ),
              ],
            ),
            if (_testResultData != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _testColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _testColor.withValues(alpha: 0.18),
                    width: 0.45,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _testColor == Colors.green
                          ? Icons.check_circle_outline
                          : Icons.error_outline,
                      color: _testColor,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _testResultData!.format(locale),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.74),
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        AppInfoBanner(
          icon: Icons.security_outlined,
          color: Colors.teal,
          title: AdminUiCopy.aiSecurityProxyTitleFor(locale),
          message: AdminUiCopy.aiSecurityProxyMessageFor(locale),
        ),
      ],
    );
  }
}

String _adminAiFailureReason(Object raw, [AppLocale? locale]) {
  return AdminUiCopy.aiFailureReason(raw, locale);
}

// ====================================================================
// 云端备份
// ====================================================================

class _BackupSettingsTab extends StatefulWidget {
  final AdminApi api;
  const _BackupSettingsTab({super.key, required this.api});
  @override
  State<_BackupSettingsTab> createState() => _BackupSettingsTabState();
}

class _BackupSettingsTabState extends State<_BackupSettingsTab> {
  bool _loading = true;
  bool _saving = false;
  bool _runningServerBackup = false;
  bool _testingReminderEmail = false;
  bool _testingAccountEmail = false;
  bool _exportingBackups = false;
  bool _exportingServerBackups = false;
  Object? _errorObject;

  bool _backupEnabled = true;
  bool _serverBackupEnabled = true;
  bool _openlistEnabled = false;
  bool _backupEmailEnabled = false;
  bool _reminderEmailEnabled = false;
  bool _accountEmailEnabled = true;
  bool _emailAutoSwitchEnabled = false;
  bool _accountSmtpUseSsl = true;
  String _emailPrimaryProvider = 'claw163';
  String _emailBackupProvider = 'resend';
  String _emailActiveSlot = 'primary';
  final _maxSizeCtrl = TextEditingController(text: '2048');
  final _intervalCtrl = TextEditingController(text: '30');
  final _retainCtrl = TextEditingController(text: '0');
  final _serverIntervalCtrl = TextEditingController(text: '720');
  final _serverRetainCtrl = TextEditingController(text: '14');
  final _openlistUrlCtrl = TextEditingController();
  final _openlistPublicUrlCtrl = TextEditingController();
  final _openlistUserCtrl = TextEditingController();
  final _openlistPasswordCtrl = TextEditingController();
  final _openlistPathCtrl = TextEditingController(text: '/duoyi-backups');
  final _emailToCtrl = TextEditingController();
  final _emailFromCtrl = TextEditingController();
  final _smtpHostCtrl = TextEditingController();
  final _smtpPortCtrl = TextEditingController(text: '465');
  final _smtpUserCtrl = TextEditingController();
  final _smtpPasswordCtrl = TextEditingController();
  final _reminderEmailToCtrl = TextEditingController();
  final _reminderEmailFromCtrl = TextEditingController();
  final _reminderSmtpHostCtrl = TextEditingController();
  final _reminderSmtpPortCtrl = TextEditingController(text: '465');
  final _reminderSmtpUserCtrl = TextEditingController();
  final _reminderSmtpPasswordCtrl = TextEditingController();
  final _emailTitleCtrl = TextEditingController(text: '多仪');
  final _emailSenderNameCtrl = TextEditingController(text: '多仪');
  final _openclawMailUserCtrl = TextEditingController();
  final _openclawMailKeyCtrl = TextEditingController();
  final _resendBaseUrlCtrl = TextEditingController();
  final _resendBaseUrlFocusNode = FocusNode();
  final _resendApiKeyCtrl = TextEditingController();
  final _resendFromCtrl = TextEditingController();
  final _systemNoticeEmailCtrl = TextEditingController();
  final _accountSmtpHostCtrl = TextEditingController();
  final _accountSmtpPortCtrl = TextEditingController(text: '465');
  final _accountSmtpUserCtrl = TextEditingController();
  final _accountSmtpFromCtrl = TextEditingController();
  final _accountSmtpPasswordCtrl = TextEditingController();
  bool _openlistPasswordMasked = false;
  bool _smtpPasswordMasked = false;
  bool _reminderSmtpPasswordMasked = false;
  bool _openclawMailKeyMasked = false;
  bool _resendApiKeyMasked = false;
  bool _accountSmtpPasswordMasked = false;

  List<Map<String, dynamic>> _backups = [];
  List<Map<String, dynamic>> _serverBackups = [];
  AdminPage? _backupPage;
  AdminPage? _serverBackupPage;
  int _backupOffset = 0;
  int _serverBackupOffset = 0;
  int _backupPageSize = _adminPageSize;
  int _serverBackupPageSize = _adminPageSize;
  String _backupQuery = '';
  String _serverBackupQuery = '';
  String _backupStatus = '';
  String _serverBackupStatus = '';
  String _backupSort = 'updated_desc';
  String _serverBackupSort = 'created_desc';
  final _backupSearchCtrl = TextEditingController();
  final _serverBackupSearchCtrl = TextEditingController();
  int _loadSerial = 0;
  Future<void> Function()? _failedLoad;

  @override
  void initState() {
    super.initState();
    I18n.localeListenable.addListener(_onLocaleChanged);
    _load();
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    I18n.localeListenable.removeListener(_onLocaleChanged);
    _maxSizeCtrl.dispose();
    _intervalCtrl.dispose();
    _retainCtrl.dispose();
    _serverIntervalCtrl.dispose();
    _serverRetainCtrl.dispose();
    _openlistUrlCtrl.dispose();
    _openlistPublicUrlCtrl.dispose();
    _openlistUserCtrl.dispose();
    _openlistPasswordCtrl.dispose();
    _openlistPathCtrl.dispose();
    _emailToCtrl.dispose();
    _emailFromCtrl.dispose();
    _smtpHostCtrl.dispose();
    _smtpPortCtrl.dispose();
    _smtpUserCtrl.dispose();
    _smtpPasswordCtrl.dispose();
    _reminderEmailToCtrl.dispose();
    _reminderEmailFromCtrl.dispose();
    _reminderSmtpHostCtrl.dispose();
    _reminderSmtpPortCtrl.dispose();
    _reminderSmtpUserCtrl.dispose();
    _reminderSmtpPasswordCtrl.dispose();
    _emailTitleCtrl.dispose();
    _emailSenderNameCtrl.dispose();
    _openclawMailUserCtrl.dispose();
    _openclawMailKeyCtrl.dispose();
    _resendBaseUrlCtrl.dispose();
    _resendBaseUrlFocusNode.dispose();
    _resendApiKeyCtrl.dispose();
    _resendFromCtrl.dispose();
    _systemNoticeEmailCtrl.dispose();
    _accountSmtpHostCtrl.dispose();
    _accountSmtpPortCtrl.dispose();
    _accountSmtpUserCtrl.dispose();
    _accountSmtpFromCtrl.dispose();
    _accountSmtpPasswordCtrl.dispose();
    _backupSearchCtrl.dispose();
    _serverBackupSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({
    int? backupOffset,
    int? serverBackupOffset,
    int? backupPageSize,
    int? serverBackupPageSize,
    String? backupQuery,
    String? serverBackupQuery,
    String? backupStatus,
    String? serverBackupStatus,
    String? backupSort,
    String? serverBackupSort,
  }) async {
    final nextBackupOffset = backupOffset ?? _backupOffset;
    final nextServerBackupOffset = serverBackupOffset ?? _serverBackupOffset;
    final nextBackupPageSize = backupPageSize ?? _backupPageSize;
    final nextServerBackupPageSize =
        serverBackupPageSize ?? _serverBackupPageSize;
    final nextBackupQuery = backupQuery ?? _backupQuery;
    final nextServerBackupQuery = serverBackupQuery ?? _serverBackupQuery;
    final nextBackupStatus = backupStatus ?? _backupStatus;
    final nextServerBackupStatus = serverBackupStatus ?? _serverBackupStatus;
    final nextBackupSort = backupSort ?? _backupSort;
    final nextServerBackupSort = serverBackupSort ?? _serverBackupSort;
    final serial = ++_loadSerial;
    setState(() {
      _loading = true;
      _errorObject = null;
    });
    try {
      final data = await widget.api.getSettings(scope: 'backup');
      if (!mounted || serial != _loadSerial) return;
      final backupPage = await widget.api.listBackupsPage(
        query: nextBackupQuery.isEmpty ? null : nextBackupQuery,
        status: nextBackupStatus.isEmpty ? null : nextBackupStatus,
        sort: nextBackupSort,
        limit: nextBackupPageSize,
        offset: nextBackupOffset,
      );
      if (!mounted || serial != _loadSerial) return;
      final serverBackupPage = await widget.api.listServerBackupsPage(
        query: nextServerBackupQuery.isEmpty ? null : nextServerBackupQuery,
        status: nextServerBackupStatus.isEmpty ? null : nextServerBackupStatus,
        sort: nextServerBackupSort,
        limit: nextServerBackupPageSize,
        offset: nextServerBackupOffset,
      );
      if (!mounted || serial != _loadSerial) return;
      _backupEnabled = data['backup_enabled'] != false;
      _maxSizeCtrl.text =
          (((data['backup_max_size_kb'] as num?) ?? 2048).toInt()).toString();
      _intervalCtrl.text =
          (((data['backup_interval_minutes'] as num?) ?? 30).toInt())
              .toString();
      _retainCtrl.text = (((data['backup_retain_days'] as num?) ?? 0).toInt())
          .toString();
      _serverBackupEnabled = data['server_backup_enabled'] != false;
      _serverIntervalCtrl.text =
          (((data['server_backup_interval_minutes'] as num?) ?? 720).toInt())
              .toString();
      _serverRetainCtrl.text =
          (((data['server_backup_retain_days'] as num?) ?? 14).toInt())
              .toString();
      _openlistEnabled = data['openlist_backup_enabled'] == true;
      _openlistUrlCtrl.text = (data['openlist_webdav_url'] ?? '').toString();
      _openlistPublicUrlCtrl.text = (data['openlist_public_url'] ?? '')
          .toString();
      _openlistUserCtrl.text = (data['openlist_username'] ?? '').toString();
      _openlistPasswordCtrl.text = (data['openlist_password'] ?? '').toString();
      _openlistPasswordMasked = data['openlist_password_set'] == true;
      _openlistPathCtrl.text =
          (data['openlist_backup_path'] ?? '/duoyi-backups').toString();
      _backupEmailEnabled = data['backup_email_enabled'] == true;
      _emailToCtrl.text = (data['backup_email_to'] ?? '').toString();
      _emailFromCtrl.text = (data['backup_email_from'] ?? '').toString();
      _smtpHostCtrl.text = (data['backup_email_smtp_host'] ?? '').toString();
      _smtpPortCtrl.text =
          (((data['backup_email_smtp_port'] as num?) ?? 465).toInt())
              .toString();
      _smtpUserCtrl.text = (data['backup_email_smtp_username'] ?? '')
          .toString();
      _smtpPasswordCtrl.text = (data['backup_email_smtp_password'] ?? '')
          .toString();
      _smtpPasswordMasked = data['backup_email_smtp_password_set'] == true;
      _reminderEmailEnabled = data['reminder_email_enabled'] == true;
      _reminderEmailToCtrl.text = (data['reminder_email_to'] ?? '').toString();
      _reminderEmailFromCtrl.text = (data['reminder_email_from'] ?? '')
          .toString();
      _reminderSmtpHostCtrl.text = (data['reminder_email_smtp_host'] ?? '')
          .toString();
      _reminderSmtpPortCtrl.text =
          (((data['reminder_email_smtp_port'] as num?) ?? 465).toInt())
              .toString();
      _reminderSmtpUserCtrl.text = (data['reminder_email_smtp_username'] ?? '')
          .toString();
      _reminderSmtpPasswordCtrl.text =
          (data['reminder_email_smtp_password'] ?? '').toString();
      _reminderSmtpPasswordMasked =
          data['reminder_email_smtp_password_set'] == true;
      _accountEmailEnabled = data['email_service_enabled'] != false;
      _emailAutoSwitchEnabled = data['email_auto_switch_enabled'] == true;
      _emailPrimaryProvider = _mailProviderValue(
        data['email_code_primary_provider'],
        fallback: 'claw163',
      );
      _emailBackupProvider = _mailProviderValue(
        data['email_code_backup_provider'],
        fallback: 'resend',
      );
      _emailActiveSlot = data['email_code_active_slot'] == 'backup'
          ? 'backup'
          : 'primary';
      _emailTitleCtrl.text = (data['email_title'] ?? '多仪').toString();
      _emailSenderNameCtrl.text = (data['email_sender_name'] ?? '多仪')
          .toString();
      _openclawMailUserCtrl.text = (data['openclaw_mail_user'] ?? '')
          .toString();
      _openclawMailKeyCtrl.text = (data['openclaw_mail_api_key'] ?? '')
          .toString();
      _openclawMailKeyMasked = data['openclaw_mail_api_key_set'] == true;
      _resendBaseUrlCtrl.text =
          (data['resend_base_url'] ?? 'https://api.resend.com').toString();
      _resendApiKeyCtrl.text = (data['resend_api_key'] ?? '').toString();
      _resendApiKeyMasked = data['resend_api_key_set'] == true;
      _resendFromCtrl.text =
          (data['resend_from'] ?? '多仪 <noreply@mail.6688667.xyz>').toString();
      _systemNoticeEmailCtrl.text = (data['system_notice_email_to'] ?? '')
          .toString();
      _accountSmtpHostCtrl.text = (data['email_smtp_host'] ?? '').toString();
      _accountSmtpPortCtrl.text =
          (((data['email_smtp_port'] as num?) ?? 465).toInt()).toString();
      _accountSmtpUserCtrl.text = (data['email_smtp_username'] ?? '')
          .toString();
      _accountSmtpFromCtrl.text = (data['email_smtp_from'] ?? '').toString();
      _accountSmtpPasswordCtrl.text = (data['email_smtp_password'] ?? '')
          .toString();
      _accountSmtpPasswordMasked = data['email_smtp_password_set'] == true;
      _accountSmtpUseSsl = data['email_smtp_use_ssl'] != false;
      _backupOffset = nextBackupOffset;
      _serverBackupOffset = nextServerBackupOffset;
      _backupPageSize = nextBackupPageSize;
      _serverBackupPageSize = nextServerBackupPageSize;
      _backupQuery = nextBackupQuery;
      _serverBackupQuery = nextServerBackupQuery;
      _backupStatus = nextBackupStatus;
      _serverBackupStatus = nextServerBackupStatus;
      _backupSort = nextBackupSort;
      _serverBackupSort = nextServerBackupSort;
      _backupPage = backupPage;
      _serverBackupPage = serverBackupPage;
      _backups = backupPage.items;
      _serverBackups = serverBackupPage.items;
      _failedLoad = null;
    } catch (e) {
      if (!mounted || serial != _loadSerial) return;
      _errorObject = e;
      _failedLoad = () => _load(
        backupOffset: nextBackupOffset,
        serverBackupOffset: nextServerBackupOffset,
        backupPageSize: nextBackupPageSize,
        serverBackupPageSize: nextServerBackupPageSize,
        backupQuery: nextBackupQuery,
        serverBackupQuery: nextServerBackupQuery,
        backupStatus: nextBackupStatus,
        serverBackupStatus: nextServerBackupStatus,
        backupSort: nextBackupSort,
        serverBackupSort: nextServerBackupSort,
      );
    } finally {
      if (mounted && serial == _loadSerial) setState(() => _loading = false);
    }
  }

  Future<void> _retryLoad() => (_failedLoad ?? _load)();

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final openlistPassword = _openlistPasswordCtrl.text.trim();
      final smtpPassword = _smtpPasswordCtrl.text.trim();
      final reminderSmtpPassword = _reminderSmtpPasswordCtrl.text.trim();
      final openclawMailKey = _openclawMailKeyCtrl.text.trim();
      final resendApiKey = _resendApiKeyCtrl.text.trim();
      final accountSmtpPassword = _accountSmtpPasswordCtrl.text.trim();
      final payload = <String, Object?>{
        'backup_enabled': _backupEnabled,
        'backup_max_size_kb': int.tryParse(_maxSizeCtrl.text.trim()) ?? 2048,
        'backup_interval_minutes':
            int.tryParse(_intervalCtrl.text.trim()) ?? 30,
        'backup_retain_days': int.tryParse(_retainCtrl.text.trim()) ?? 0,
        'server_backup_enabled': _serverBackupEnabled,
        'server_backup_interval_minutes':
            int.tryParse(_serverIntervalCtrl.text.trim()) ?? 720,
        'server_backup_retain_days':
            int.tryParse(_serverRetainCtrl.text.trim()) ?? 14,
        'openlist_backup_enabled': _openlistEnabled,
        'openlist_webdav_url': _openlistUrlCtrl.text.trim(),
        'openlist_public_url': _openlistPublicUrlCtrl.text.trim(),
        'openlist_username': _openlistUserCtrl.text.trim(),
        'openlist_backup_path': _openlistPathCtrl.text.trim(),
        'backup_email_enabled': _backupEmailEnabled,
        'backup_email_to': _emailToCtrl.text.trim(),
        'backup_email_from': _emailFromCtrl.text.trim(),
        'backup_email_smtp_host': _smtpHostCtrl.text.trim(),
        'backup_email_smtp_port':
            int.tryParse(_smtpPortCtrl.text.trim()) ?? 465,
        'backup_email_smtp_username': _smtpUserCtrl.text.trim(),
        'reminder_email_enabled': _reminderEmailEnabled,
        'reminder_email_to': _reminderEmailToCtrl.text.trim(),
        'reminder_email_from': _reminderEmailFromCtrl.text.trim(),
        'reminder_email_smtp_host': _reminderSmtpHostCtrl.text.trim(),
        'reminder_email_smtp_port':
            int.tryParse(_reminderSmtpPortCtrl.text.trim()) ?? 465,
        'reminder_email_smtp_username': _reminderSmtpUserCtrl.text.trim(),
        'email_service_enabled': _accountEmailEnabled,
        'email_title': _emailTitleCtrl.text.trim(),
        'email_sender_name': _emailSenderNameCtrl.text.trim(),
        'email_code_primary_provider': _emailPrimaryProvider,
        'email_code_backup_provider': _emailBackupProvider,
        'email_code_active_slot': _emailActiveSlot,
        'email_auto_switch_enabled': _emailAutoSwitchEnabled,
        'openclaw_mail_enabled':
            _emailPrimaryProvider == 'claw163' ||
            _emailBackupProvider == 'claw163',
        'openclaw_mail_user': _openclawMailUserCtrl.text.trim(),
        'resend_base_url': _resendBaseUrlCtrl.text.trim(),
        'resend_from': _resendFromCtrl.text.trim(),
        'system_notice_email_to': _systemNoticeEmailCtrl.text.trim(),
        'email_smtp_host': _accountSmtpHostCtrl.text.trim(),
        'email_smtp_port':
            int.tryParse(_accountSmtpPortCtrl.text.trim()) ?? 465,
        'email_smtp_username': _accountSmtpUserCtrl.text.trim(),
        'email_smtp_from': _accountSmtpFromCtrl.text.trim(),
        'email_smtp_use_ssl': _accountSmtpUseSsl,
      };
      if (!(_openlistPasswordMasked && openlistPassword.contains('***'))) {
        payload['openlist_password'] = openlistPassword;
      }
      if (!(_smtpPasswordMasked && smtpPassword.contains('***'))) {
        payload['backup_email_smtp_password'] = smtpPassword;
      }
      if (!(_reminderSmtpPasswordMasked &&
          reminderSmtpPassword.contains('***'))) {
        payload['reminder_email_smtp_password'] = reminderSmtpPassword;
      }
      if (!(_openclawMailKeyMasked && openclawMailKey.contains('***'))) {
        payload['openclaw_mail_api_key'] = openclawMailKey;
      }
      if (!(_resendApiKeyMasked && resendApiKey.contains('***'))) {
        payload['resend_api_key'] = resendApiKey;
      }
      if (!(_accountSmtpPasswordMasked &&
          accountSmtpPassword.contains('***'))) {
        payload['email_smtp_password'] = accountSmtpPassword;
      }
      await widget.api.client.patch('/api/admin/settings', payload);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: _AdminFeedbackText(
            (locale) => AdminUiCopy.backupConfigSavedFor(locale),
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: _AdminFeedbackText(
              (locale) => _adminActionErrorMessage(
                e,
                AdminUiCopy.actionSaveBackupConfigFor(locale),
                locale,
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _runServerBackup() async {
    setState(() => _runningServerBackup = true);
    try {
      await widget.api.runServerBackup();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: _AdminFeedbackText(
              (locale) => AdminUiCopy.serverBackupExecutedFor(locale),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: _AdminFeedbackText(
              (locale) => _adminActionErrorMessage(
                e,
                AdminUiCopy.actionRunServerBackupFor(locale),
                locale,
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _runningServerBackup = false);
    }
  }

  Future<void> _testReminderEmail() async {
    setState(() => _testingReminderEmail = true);
    try {
      final res = await widget.api.testReminderEmail();
      if (mounted) {
        final recipient = (res['recipient'] ?? '').toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: _AdminFeedbackText(
              (locale) => recipient.isEmpty
                  ? AdminUiCopy.testEmailSentFor(locale)
                  : AdminUiCopy.testEmailSentTo(recipient, locale),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: _AdminFeedbackText(
              (locale) => _adminActionErrorMessage(
                e,
                AdminUiCopy.actionSendReminderTestEmailFor(locale),
                locale,
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _testingReminderEmail = false);
    }
  }

  Future<void> _testAccountEmail() async {
    setState(() => _testingAccountEmail = true);
    try {
      final res = await widget.api.testAccountEmail();
      if (mounted) {
        final recipient = (res['recipient'] ?? '').toString();
        final provider = (res['provider'] ?? '').toString();
        final channel = provider.isEmpty ? '' : ' · $provider';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: _AdminFeedbackText(
              (locale) => recipient.isEmpty
                  ? AdminUiCopy.accountTestEmailSent(channel, locale)
                  : AdminUiCopy.accountTestEmailSentTo(
                      recipient,
                      channel,
                      locale,
                    ),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: _AdminFeedbackText(
              (locale) => _adminActionErrorMessage(
                e,
                AdminUiCopy.actionSendAccountTestEmailFor(locale),
                locale,
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _testingAccountEmail = false);
    }
  }

  String _mailProviderValue(Object? value, {required String fallback}) {
    final raw = (value ?? fallback).toString().trim().toLowerCase();
    final normalized = switch (raw) {
      'openclaw' || 'openclaw_mail' => 'claw163',
      _ => raw,
    };
    return {'claw163', 'resend', 'smtp', 'none'}.contains(normalized)
        ? normalized
        : fallback;
  }

  /// 邮件配置字段：窄屏/放大时长标签外置换行（与 Resend 服务地址一致），
  /// 字段始终位于同一槽位，切换布局时保留 focus/selection。
  Widget _mailLabeled(
    BuildContext context, {
    required bool external,
    required String label,
    required Widget field,
  }) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (external)
          ExcludeSemantics(
            child: Text(
              label,
              style:
                  (theme.inputDecorationTheme.labelStyle ??
                          theme.textTheme.bodyMedium ??
                          const TextStyle())
                      .copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.normal,
                      ),
            ),
          )
        else
          const SizedBox.shrink(),
        SizedBox(height: external ? 6 : 0),
        Semantics(label: external ? label : null, child: field),
      ],
    );
  }

  InputDecoration _mailDecoration({
    required bool external,
    required String label,
    required IconData icon,
    String? helperText,
  }) => InputDecoration(
    constraints: const BoxConstraints(minHeight: 44),
    labelText: external ? null : label,
    helperText: helperText,
    prefixIcon: Icon(icon),
  );

  Widget _mailTextField(
    BuildContext context, {
    required bool external,
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    TextInputType? keyboardType,
    String? helperText,
  }) => _mailLabeled(
    context,
    external: external,
    label: label,
    field: TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      decoration: _mailDecoration(
        external: external,
        label: label,
        icon: icon,
        helperText: helperText,
      ),
    ),
  );

  Widget _mailDropdown(
    BuildContext context, {
    required bool external,
    required String initialValue,
    required String label,
    required IconData icon,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) => _mailLabeled(
    context,
    external: external,
    label: label,
    field: AppDropdownField<String>(
      initialValue: initialValue,
      wrapSelectedText: true,
      decoration: _mailDecoration(external: external, label: label, icon: icon),
      items: items,
      onChanged: onChanged,
    ),
  );

  List<DropdownMenuItem<String>> _mailProviderItems([AppLocale? locale]) => [
    const DropdownMenuItem(value: 'claw163', child: Text('Claw163')),
    const DropdownMenuItem(value: 'resend', child: Text('Resend')),
    const DropdownMenuItem(value: 'smtp', child: Text('SMTP')),
    DropdownMenuItem(
      value: 'none',
      child: Text(AdminUiCopy.mailProviderDisabledFor(locale)),
    ),
  ];

  Future<void> _wipe(Map<String, dynamic> row) async {
    final username = (row['username'] ?? '').toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => ValueListenableBuilder<AppLocale>(
        valueListenable: I18n.localeListenable,
        builder: (context, locale, _) {
          return AppDialog(
            title: Text(AdminUiCopy.wipeBackupDialogTitle(username, locale)),
            icon: const Icon(Icons.cloud_off_outlined),
            content: _AdminFeedbackText(
              (locale) => AdminUiCopy.wipeBackupDialogContentFor(locale),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(AdminUiCopy.cancelBtnFor(locale)),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                  foregroundColor: Theme.of(ctx).colorScheme.onError,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(AdminUiCopy.wipeFor(locale)),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.wipeBackup(row['user_id'].toString());
      if (!mounted) return;
      final nextOffset = _backups.length == 1 && _backupOffset > 0
          ? (_backupOffset - _backupPageSize).clamp(0, _backupOffset)
          : _backupOffset;
      await _load(backupOffset: nextOffset);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: _AdminFeedbackText(
              (locale) => _adminActionErrorMessage(
                e,
                AdminUiCopy.actionWipeBackupFor(locale),
                locale,
              ),
            ),
          ),
        );
      }
    }
  }

  Future<void> _exportBackupsCsv() async {
    setState(() => _exportingBackups = true);
    final locale = I18n.current;
    try {
      final csv = await widget.api.exportBackupsCsv(
        query: _backupQuery.isEmpty ? null : _backupQuery,
        status: _backupStatus.isEmpty ? null : _backupStatus,
        sort: _backupSort,
      );
      await _shareAdminCsv(
        csv,
        prefix: 'duoyi_backups',
        text: AdminUiCopy.exportUserBackupsTextFor(locale),
        subject: AdminUiCopy.exportUserBackupsSubjectFor(locale),
        successLabel: AdminUiCopy.exportUserBackupsSuccessFor,
      );
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: _AdminFeedbackText(
              (locale) => userVisibleApiError(e, locale: locale),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exportingBackups = false);
    }
  }

  Future<void> _exportServerBackupsCsv() async {
    setState(() => _exportingServerBackups = true);
    final locale = I18n.current;
    try {
      final csv = await widget.api.exportServerBackupsCsv(
        query: _serverBackupQuery.isEmpty ? null : _serverBackupQuery,
        status: _serverBackupStatus.isEmpty ? null : _serverBackupStatus,
        sort: _serverBackupSort,
      );
      await _shareAdminCsv(
        csv,
        prefix: 'duoyi_server_backups',
        text: AdminUiCopy.exportServerBackupsTextFor(locale),
        subject: AdminUiCopy.exportServerBackupsSubjectFor(locale),
        successLabel: AdminUiCopy.exportServerBackupsSuccessFor,
      );
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: _AdminFeedbackText(
              (locale) => userVisibleApiError(e, locale: locale),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exportingServerBackups = false);
    }
  }

  Future<void> _shareAdminCsv(
    String csv, {
    required String prefix,
    required String text,
    required String subject,
    required String Function(AppLocale) successLabel,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/${prefix}_${DateTime.now().millisecondsSinceEpoch}.csv',
    );
    await file.writeAsString(csv, flush: true);
    await Clipboard.setData(ClipboardData(text: file.path));
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], text: text, subject: subject),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: _AdminFeedbackText(
          (locale) => AdminUiCopy.shareAdminCsvSuccess(
            successLabel(locale),
            file.path,
            locale,
          ),
        ),
      ),
    );
  }

  Widget _backupStatusChip(String label, String value) {
    final selected = _backupStatus == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => _load(backupStatus: value, backupOffset: 0),
      ),
    );
  }

  Widget _serverBackupStatusChip(String label, String value) {
    final selected = _serverBackupStatus == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) =>
            _load(serverBackupStatus: value, serverBackupOffset: 0),
      ),
    );
  }

  Widget _backupRecordViewport(BuildContext context, Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = (MediaQuery.textScalerOf(context).scale(12) / 12)
            .clamp(1.0, double.infinity);
        return SingleChildScrollView(
          child: SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight * textScale,
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildBackupRecordTabs(
    BuildContext context, {
    required ThemeData theme,
    required ColorScheme cs,
    required int totalKb,
    required AppLocale locale,
  }) {
    return DecoratedBox(
      key: const ValueKey('admin_backup_record_tabs'),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: cs.outlineVariant.withValues(
            alpha: theme.brightness == Brightness.dark ? 0.10 : 0.12,
          ),
          width: 0.45,
        ),
      ),
      child: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelStyle: appSecondaryMenuItemTextStyle(context),
              unselectedLabelStyle: appSecondaryMenuItemTextStyle(context),
              tabs: [
                Tab(text: AdminUiCopy.serverBackupRecordsTabFor(locale)),
                Tab(text: AdminUiCopy.allUserBackupsTabFor(locale)),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _backupRecordViewport(
                    context,
                    _buildServerBackupRecords(
                      theme: theme,
                      cs: cs,
                      locale: locale,
                    ),
                  ),
                  _backupRecordViewport(
                    context,
                    _buildUserBackupRecords(
                      theme: theme,
                      cs: cs,
                      totalKb: totalKb,
                      locale: locale,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServerBackupRecords({
    required ThemeData theme,
    required ColorScheme cs,
    required AppLocale locale,
  }) {
    return Column(
      key: const ValueKey('admin_backup_server_panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          child: AppSectionHeader(
            title: AdminUiCopy.serverBackupRecordsTabFor(locale),
            subtitle: _adminPageSummary(_serverBackupPage, locale),
            actionLabel: _exportingServerBackups
                ? AdminUiCopy.exportingEllipsis(locale)
                : AdminUiCopy.exportFilteredResultsFor(locale),
            actionIcon: Icons.ios_share_outlined,
            onAction: _exportingServerBackups ? null : _exportServerBackupsCsv,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
          child: TextField(
            controller: _serverBackupSearchCtrl,
            decoration: InputDecoration(
              hintText: AdminUiCopy.searchServerBackupsHintFor(locale),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _serverBackupQuery.isEmpty
                  ? null
                  : IconButton(
                      tooltip: AdminUiCopy.clearServerBackupSearchTooltipFor(
                        locale,
                      ),
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _serverBackupSearchCtrl.clear();
                        _load(serverBackupQuery: '', serverBackupOffset: 0);
                      },
                    ),
              isDense: true,
            ),
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _load(
              serverBackupQuery: _serverBackupSearchCtrl.text.trim(),
              serverBackupOffset: 0,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
          child: _AdminChipWrap(
            padding: EdgeInsets.zero,
            children: [
              _serverBackupStatusChip(
                AdminUiCopy.allBackupsChipFor(locale),
                '',
              ),
              _serverBackupStatusChip(
                AdminUiCopy.uploadedChipFor(locale),
                'uploaded',
              ),
              _serverBackupStatusChip(
                AdminUiCopy.localOnlyChipFor(locale),
                'local_only',
              ),
              _serverBackupStatusChip(
                AdminUiCopy.remoteFailedChipFor(locale),
                'local_created_remote_failed',
              ),
              _serverBackupStatusChip(
                AdminUiCopy.createdChipFor(locale),
                'created',
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
          child: Row(
            children: [
              Expanded(
                child: AppDropdownField<String>(
                  initialValue: _serverBackupSort,
                  labelText: AdminUiCopy.serverBackupSortLabelFor(locale),
                  items: [
                    DropdownMenuItem(
                      value: 'created_desc',
                      child: Text(
                        _adminServerBackupSortLabel('created_desc', locale),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'size_desc',
                      child: Text(
                        _adminServerBackupSortLabel('size_desc', locale),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'size_asc',
                      child: Text(
                        _adminServerBackupSortLabel('size_asc', locale),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'status_asc',
                      child: Text(
                        _adminServerBackupSortLabel('status_asc', locale),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'filename_asc',
                      child: Text(
                        _adminServerBackupSortLabel('filename_asc', locale),
                      ),
                    ),
                  ],
                  onChanged: (value) => _load(
                    serverBackupSort: value ?? 'created_desc',
                    serverBackupOffset: 0,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: _loading
                    ? null
                    : () => _load(serverBackupOffset: _serverBackupOffset),
                icon: const Icon(Icons.refresh, size: 16),
                label: Text(AdminUiCopy.refreshBtnFor(locale)),
              ),
            ],
          ),
        ),
        Expanded(
          child: _serverBackups.isEmpty
              ? Center(
                  child: Text(
                    AdminUiCopy.emptyServerBackupsMessageFor(locale),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.58),
                    ),
                  ),
                )
              : ListView.builder(
                  key: const ValueKey('admin_backup_server_records'),
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                  itemCount: _serverBackups.length,
                  itemBuilder: (context, index) {
                    final b = _serverBackups[index];
                    final status = (b['status'] ?? '-').toString();
                    return _AdminListTileCard(
                      margin: const EdgeInsets.only(bottom: 8),
                      dense: true,
                      leading: Icon(Icons.backup_outlined, color: cs.primary),
                      title: Text((b['filename'] ?? '-').toString()),
                      subtitle: Text(
                        '${b['created_at'] ?? '-'} · ${_adminStatusLabel(status, locale)} · ${b['size_bytes'] ?? 0} ${AdminUiCopy.bytesUnit(locale)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.62),
                        ),
                      ),
                    );
                  },
                ),
        ),
        _AdminPaginationBar(
          barKey: const ValueKey('admin_backup_server_pagination'),
          page: _serverBackupPage,
          loading: _loading,
          pageSize: _serverBackupPageSize,
          locale: locale,
          onPageSizeChanged: (value) =>
              _load(serverBackupPageSize: value, serverBackupOffset: 0),
          onPrevious: () => _load(
            serverBackupOffset: (_serverBackupOffset - _serverBackupPageSize)
                .clamp(0, _serverBackupOffset),
          ),
          onNext: () => _load(
            serverBackupOffset: _serverBackupOffset + _serverBackupPageSize,
          ),
          onJumpToPage: (page) =>
              _load(serverBackupOffset: (page - 1) * _serverBackupPageSize),
        ),
      ],
    );
  }

  Widget _buildUserBackupRecords({
    required ThemeData theme,
    required ColorScheme cs,
    required int totalKb,
    required AppLocale locale,
  }) {
    return Column(
      key: const ValueKey('admin_backup_user_panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          child: AppSectionHeader(
            title: AdminUiCopy.allUserBackupsTabFor(locale),
            subtitle:
                '${_adminPageSummary(_backupPage, locale)} · ${AdminUiCopy.pageTotalMbLabel((totalKb / 1024).toStringAsFixed(1), locale)}',
            actionLabel: _exportingBackups
                ? AdminUiCopy.exportingEllipsis(locale)
                : AdminUiCopy.exportFilteredResultsFor(locale),
            actionIcon: Icons.ios_share_outlined,
            onAction: _exportingBackups ? null : _exportBackupsCsv,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
          child: TextField(
            controller: _backupSearchCtrl,
            decoration: InputDecoration(
              hintText: AdminUiCopy.searchUserBackupsHintFor(locale),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _backupQuery.isEmpty
                  ? null
                  : IconButton(
                      tooltip: AdminUiCopy.clearUserBackupSearchTooltipFor(
                        locale,
                      ),
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _backupSearchCtrl.clear();
                        _load(backupQuery: '', backupOffset: 0);
                      },
                    ),
              isDense: true,
            ),
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _load(
              backupQuery: _backupSearchCtrl.text.trim(),
              backupOffset: 0,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
          child: _AdminChipWrap(
            padding: EdgeInsets.zero,
            children: [
              _backupStatusChip(AdminUiCopy.allUsersChipFor(locale), ''),
              _backupStatusChip(
                AdminUiCopy.hasSnapshotChipFor(locale),
                'synced',
              ),
              _backupStatusChip(AdminUiCopy.noSnapshotChipFor(locale), 'empty'),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
          child: Row(
            children: [
              Expanded(
                child: AppDropdownField<String>(
                  initialValue: _backupSort,
                  labelText: AdminUiCopy.userBackupSortLabelFor(locale),
                  items: [
                    DropdownMenuItem(
                      value: 'updated_desc',
                      child: Text(
                        _adminBackupSortLabel('updated_desc', locale),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'username_asc',
                      child: Text(
                        _adminBackupSortLabel('username_asc', locale),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'size_desc',
                      child: Text(_adminBackupSortLabel('size_desc', locale)),
                    ),
                    DropdownMenuItem(
                      value: 'size_asc',
                      child: Text(_adminBackupSortLabel('size_asc', locale)),
                    ),
                    DropdownMenuItem(
                      value: 'version_desc',
                      child: Text(
                        _adminBackupSortLabel('version_desc', locale),
                      ),
                    ),
                  ],
                  onChanged: (value) => _load(
                    backupSort: value ?? 'updated_desc',
                    backupOffset: 0,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: _loading
                    ? null
                    : () => _load(backupOffset: _backupOffset),
                icon: const Icon(Icons.refresh, size: 16),
                label: Text(AdminUiCopy.refreshBtnFor(locale)),
              ),
            ],
          ),
        ),
        Expanded(
          child: _backups.isEmpty
              ? Center(
                  child: Text(
                    AdminUiCopy.emptyUserBackupsMessageFor(locale),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.58),
                    ),
                  ),
                )
              : ListView.builder(
                  key: const ValueKey('admin_backup_user_records'),
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                  itemCount: _backups.length,
                  itemBuilder: (context, index) {
                    final b = _backups[index];
                    final email = (b['email'] ?? '').toString();
                    final displayName = (b['display_name'] ?? '').toString();
                    final hasSnapshot = b['has_snapshot'] == true;
                    final updated = hasSnapshot
                        ? (b['updated_at'] ?? AdminUiCopy.noSyncTime(locale))
                              .toString()
                        : AdminUiCopy.noSyncSnapshot(locale);
                    return _AdminListTileCard(
                      margin: const EdgeInsets.only(bottom: 8),
                      dense: true,
                      leading: Icon(
                        Icons.cloud_done_outlined,
                        color: cs.primary,
                      ),
                      title: Text(b['username'].toString()),
                      subtitle: Text(
                        [
                          if (displayName.isNotEmpty)
                            '${AdminUiCopy.nicknamePrefix(locale)}: $displayName',
                          if (email.isNotEmpty)
                            '${AdminUiCopy.emailPrefix(locale)}: $email',
                          updated,
                          '${AdminUiCopy.syncVersionPrefix(locale)} ${b['sync_version'] ?? 0}',
                          '${b['size_kb']} KB',
                        ].join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.62),
                        ),
                      ),
                      trailing: IconButton(
                        tooltip: AdminUiCopy.wipeBackupTooltipFor(locale),
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _wipe(b),
                      ),
                    );
                  },
                ),
        ),
        _AdminPaginationBar(
          barKey: const ValueKey('admin_backup_user_pagination'),
          page: _backupPage,
          loading: _loading,
          pageSize: _backupPageSize,
          locale: locale,
          onPageSizeChanged: (value) =>
              _load(backupPageSize: value, backupOffset: 0),
          onPrevious: () => _load(
            backupOffset: (_backupOffset - _backupPageSize).clamp(
              0,
              _backupOffset,
            ),
          ),
          onNext: () => _load(backupOffset: _backupOffset + _backupPageSize),
          onJumpToPage: (page) =>
              _load(backupOffset: (page - 1) * _backupPageSize),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final locale = I18n.current;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_errorObject != null) {
      return _AdminErrorState(
        message: _adminErrorMessage(
          _errorObject!,
          AdminUiCopy.backupSettingsTabTitleFor(locale),
          locale,
        ),
        onRetry: _retryLoad,
      );
    }
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final media = MediaQuery.of(context);
    final isCompactOrScaled =
        media.size.width < 360 || media.textScaler.scale(1.0) > 1.25;

    final totalKb = _backups.fold<int>(
      0,
      (s, e) => s + ((e['size_kb'] as int?) ?? 0),
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _AdminSettingsSection(
          title: AdminUiCopy.cloudBackupSectionTitleFor(locale),
          subtitle: AdminUiCopy.cloudBackupSectionSubtitleFor(locale),
          children: [
            AppSwitchTile(
              icon: Icons.cloud_sync_outlined,
              color: cs.primary,
              value: _backupEnabled,
              title: AdminUiCopy.cloudBackupEnableTitleFor(locale),
              subtitle: AdminUiCopy.cloudBackupEnableSubtitleFor(locale),
              onChanged: (v) => setState(() => _backupEnabled = v),
            ),
            const SizedBox(height: 10),
            _AdminSettingsTextField(
              controller: _maxSizeCtrl,
              label: AdminUiCopy.backupMaxSizeLabelFor(locale),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                helperText: AdminUiCopy.backupMaxSizeHelperFor(locale),
                prefixIcon: const Icon(Icons.storage_outlined),
              ),
            ),
            const SizedBox(height: 10),
            _AdminSettingsTextField(
              controller: _intervalCtrl,
              label: AdminUiCopy.backupIntervalLabelFor(locale),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                helperText: AdminUiCopy.backupIntervalHelperFor(locale),
                prefixIcon: const Icon(Icons.update_outlined),
              ),
            ),
            const SizedBox(height: 10),
            _AdminSettingsTextField(
              controller: _retainCtrl,
              label: AdminUiCopy.backupRetainLabelFor(locale),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                helperText: AdminUiCopy.backupRetainHelperFor(locale),
                prefixIcon: const Icon(Icons.history_outlined),
              ),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(
                  _saving
                      ? AdminUiCopy.savingEllipsis(locale)
                      : AdminUiCopy.saveBtnFor(locale),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _AdminSettingsSection(
          title: AdminUiCopy.serverBackupSectionTitleFor(locale),
          subtitle: AdminUiCopy.serverBackupSectionSubtitleFor(locale),
          children: [
            AppSwitchTile(
              icon: Icons.dns_outlined,
              color: Colors.indigo,
              value: _serverBackupEnabled,
              title: AdminUiCopy.serverBackupEnableTitleFor(locale),
              subtitle: AdminUiCopy.serverBackupEnableSubtitleFor(locale),
              onChanged: (v) => setState(() => _serverBackupEnabled = v),
            ),
            const SizedBox(height: 10),
            _adminResponsiveTwoColumn(
              context: context,
              first: _AdminSettingsTextField(
                controller: _serverIntervalCtrl,
                label: AdminUiCopy.serverBackupIntervalLabelFor(locale),
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.schedule_outlined),
                ),
              ),
              second: _AdminSettingsTextField(
                controller: _serverRetainCtrl,
                label: AdminUiCopy.serverBackupRetainLabelFor(locale),
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.history_toggle_off_outlined),
                ),
              ),
            ),
            const SizedBox(height: 12),
            AppSwitchTile(
              icon: Icons.cloud_upload_outlined,
              color: Colors.blue,
              value: _openlistEnabled,
              title: AdminUiCopy.openlistEnableTitleFor(locale),
              subtitle: AdminUiCopy.openlistEnableSubtitleFor(locale),
              onChanged: (v) => setState(() => _openlistEnabled = v),
            ),
            const SizedBox(height: 10),
            _AdminSettingsTextField(
              controller: _openlistUrlCtrl,
              label: 'OpenList WebDAV URL',
              decoration: const InputDecoration(
                hintText: 'http://127.0.0.1:5244/dav',
                prefixIcon: Icon(Icons.link_outlined),
              ),
            ),
            const SizedBox(height: 10),
            _AdminSettingsTextField(
              controller: _openlistPublicUrlCtrl,
              label: AdminUiCopy.openlistPublicUrlLabelFor(locale),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.public_outlined),
              ),
            ),
            const SizedBox(height: 10),
            _adminResponsiveTwoColumn(
              context: context,
              first: _AdminSettingsTextField(
                controller: _openlistUserCtrl,
                label: AdminUiCopy.openlistUserLabelFor(locale),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.person_outline),
                ),
              ),
              second: _AdminSettingsTextField(
                controller: _openlistPasswordCtrl,
                label: AdminUiCopy.openlistPasswordLabelFor(locale),
                obscureText: true,
                decoration: InputDecoration(
                  helperText: _openlistPasswordMasked
                      ? AdminUiCopy.configuredLeaveUnchanged(locale)
                      : null,
                  prefixIcon: const Icon(Icons.password_outlined),
                ),
              ),
            ),
            const SizedBox(height: 10),
            _AdminSettingsTextField(
              controller: _openlistPathCtrl,
              label: AdminUiCopy.openlistPathLabelFor(locale),
              decoration: InputDecoration(
                hintText: '/duoyi-backups',
                prefixIcon: const Icon(Icons.folder_outlined),
              ),
            ),
            const SizedBox(height: 12),
            AppSwitchTile(
              icon: Icons.mark_email_read_outlined,
              color: Colors.teal,
              value: _backupEmailEnabled,
              title: AdminUiCopy.backupEmailEnableTitleFor(locale),
              subtitle: AdminUiCopy.backupEmailEnableSubtitleFor(locale),
              onChanged: (v) => setState(() => _backupEmailEnabled = v),
            ),
            const SizedBox(height: 10),
            _adminResponsiveTwoColumn(
              context: context,
              first: _mailTextField(
                context,
                external: isCompactOrScaled,
                controller: _emailToCtrl,
                label: AdminUiCopy.noticeRecipientLabelFor(locale),
                icon: Icons.alternate_email,
              ),
              second: _mailTextField(
                context,
                external: isCompactOrScaled,
                controller: _emailFromCtrl,
                label: AdminUiCopy.senderLabelFor(locale),
                icon: Icons.outgoing_mail,
              ),
            ),
            const SizedBox(height: 10),
            _mailTextField(
              context,
              external: isCompactOrScaled,
              controller: _smtpHostCtrl,
              label: 'SMTP Host',
              icon: Icons.dns_outlined,
            ),
            const SizedBox(height: 10),
            _adminResponsiveTwoColumn(
              context: context,
              first: _mailTextField(
                context,
                external: isCompactOrScaled,
                controller: _smtpPortCtrl,
                keyboardType: TextInputType.number,
                label: AdminUiCopy.smtpPortLabelFor(locale),
                icon: Icons.numbers_outlined,
              ),
              second: _mailTextField(
                context,
                external: isCompactOrScaled,
                controller: _smtpUserCtrl,
                label: AdminUiCopy.smtpUsernameLabelFor(locale),
                icon: Icons.person_outline,
              ),
            ),
            const SizedBox(height: 10),
            _mailTextField(
              context,
              external: isCompactOrScaled,
              controller: _smtpPasswordCtrl,
              obscureText: true,
              label: AdminUiCopy.smtpPasswordLabelFor(locale),
              helperText: _smtpPasswordMasked
                  ? AdminUiCopy.configuredLeaveUnchanged(locale)
                  : null,
              icon: Icons.key_outlined,
            ),
            const SizedBox(height: 16),
            AppSwitchTile(
              icon: Icons.mark_email_read_outlined,
              color: Colors.indigo,
              value: _accountEmailEnabled,
              title: AdminUiCopy.accountEmailEnableTitleFor(locale),
              subtitle: AdminUiCopy.accountEmailEnableSubtitleFor(locale),
              onChanged: (v) => setState(() => _accountEmailEnabled = v),
            ),
            const SizedBox(height: 10),
            _mailTextField(
              context,
              external: isCompactOrScaled,
              controller: _emailTitleCtrl,
              label: AdminUiCopy.emailTitleLabelFor(locale),
              helperText: AdminUiCopy.emailTitleHelperFor(locale),
              icon: Icons.title_outlined,
            ),
            const SizedBox(height: 10),
            _mailTextField(
              context,
              external: isCompactOrScaled,
              controller: _emailSenderNameCtrl,
              label: AdminUiCopy.emailSenderNameLabelFor(locale),
              icon: Icons.badge_outlined,
            ),
            const SizedBox(height: 10),
            _adminResponsiveTwoColumn(
              context: context,
              first: _mailDropdown(
                context,
                external: isCompactOrScaled,
                initialValue: _emailPrimaryProvider,
                label: AdminUiCopy.primaryChannelLabelFor(locale),
                icon: Icons.route_outlined,
                items: _mailProviderItems(locale),
                onChanged: (v) =>
                    setState(() => _emailPrimaryProvider = v ?? 'claw163'),
              ),
              second: _mailDropdown(
                context,
                external: isCompactOrScaled,
                initialValue: _emailBackupProvider,
                label: AdminUiCopy.backupChannelLabelFor(locale),
                icon: Icons.alt_route_outlined,
                items: _mailProviderItems(locale),
                onChanged: (v) =>
                    setState(() => _emailBackupProvider = v ?? 'resend'),
              ),
            ),
            const SizedBox(height: 10),
            _adminResponsiveTwoColumn(
              context: context,
              first: _mailDropdown(
                context,
                external: isCompactOrScaled,
                initialValue: _emailActiveSlot,
                label: AdminUiCopy.activePriorityChannelLabelFor(locale),
                icon: Icons.swap_horiz_outlined,
                items: [
                  DropdownMenuItem(
                    value: 'primary',
                    child: Text(AdminUiCopy.primaryChannelItemFor(locale)),
                  ),
                  DropdownMenuItem(
                    value: 'backup',
                    child: Text(AdminUiCopy.backupChannelItemFor(locale)),
                  ),
                ],
                onChanged: (v) =>
                    setState(() => _emailActiveSlot = v ?? 'primary'),
              ),
              second: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(AdminUiCopy.autoSwitchOnSuccessTitleFor(locale)),
                value: _emailAutoSwitchEnabled,
                onChanged: (v) => setState(() => _emailAutoSwitchEnabled = v),
              ),
            ),
            const SizedBox(height: 10),
            _adminResponsiveTwoColumn(
              context: context,
              first: _mailTextField(
                context,
                external: isCompactOrScaled,
                controller: _openclawMailUserCtrl,
                label: AdminUiCopy.claw163EmailLabelFor(locale),
                icon: Icons.alternate_email,
              ),
              second: _mailTextField(
                context,
                external: isCompactOrScaled,
                controller: _openclawMailKeyCtrl,
                obscureText: true,
                label: 'Claw163 API Key',
                helperText: _openclawMailKeyMasked
                    ? AdminUiCopy.configuredLeaveUnchanged(locale)
                    : null,
                icon: Icons.key_outlined,
              ),
            ),
            if (isCompactOrScaled) ...[
              const SizedBox(height: 10),
              ExcludeSemantics(
                child: Text(
                  AdminUiCopy.resendBaseUrlLabelFor(locale),
                  style:
                      (theme.inputDecorationTheme.labelStyle ??
                              theme.textTheme.bodyMedium ??
                              const TextStyle())
                          .copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.normal,
                          ),
                ),
              ),
              const SizedBox(height: 6),
            ] else
              const SizedBox(height: 10),
            Semantics(
              label: isCompactOrScaled
                  ? AdminUiCopy.resendBaseUrlLabelFor(locale)
                  : null,
              child: TextField(
                key: const ValueKey('admin_resend_base_url_field'),
                controller: _resendBaseUrlCtrl,
                focusNode: _resendBaseUrlFocusNode,
                decoration: InputDecoration(
                  constraints: const BoxConstraints(minHeight: 44),
                  labelText: isCompactOrScaled
                      ? null
                      : AdminUiCopy.resendBaseUrlLabelFor(locale),
                  hintText: 'https://api.resend.com',
                  prefixIcon: const Icon(Icons.link_outlined),
                ),
              ),
            ),
            const SizedBox(height: 10),
            _adminResponsiveTwoColumn(
              context: context,
              first: _mailTextField(
                context,
                external: isCompactOrScaled,
                controller: _resendApiKeyCtrl,
                obscureText: true,
                label: 'Resend API Key',
                helperText: _resendApiKeyMasked
                    ? AdminUiCopy.configuredLeaveUnchanged(locale)
                    : null,
                icon: Icons.key_outlined,
              ),
              second: _mailTextField(
                context,
                external: isCompactOrScaled,
                controller: _resendFromCtrl,
                label: AdminUiCopy.resendSenderLabelFor(locale),
                icon: Icons.outgoing_mail,
              ),
            ),
            const SizedBox(height: 10),
            _mailTextField(
              context,
              external: isCompactOrScaled,
              controller: _systemNoticeEmailCtrl,
              label: AdminUiCopy.systemNoticeRecipientLabelFor(locale),
              helperText: AdminUiCopy.systemNoticeRecipientHelperFor(locale),
              icon: Icons.notifications_active_outlined,
            ),
            const SizedBox(height: 10),
            _mailTextField(
              context,
              external: isCompactOrScaled,
              controller: _accountSmtpHostCtrl,
              label: AdminUiCopy.accountSmtpHostLabelFor(locale),
              icon: Icons.dns_outlined,
            ),
            const SizedBox(height: 10),
            _adminResponsiveTwoColumn(
              context: context,
              first: _mailTextField(
                context,
                external: isCompactOrScaled,
                controller: _accountSmtpPortCtrl,
                keyboardType: TextInputType.number,
                label: AdminUiCopy.accountSmtpPortLabelFor(locale),
                icon: Icons.numbers_outlined,
              ),
              second: _mailTextField(
                context,
                external: isCompactOrScaled,
                controller: _accountSmtpUserCtrl,
                label: AdminUiCopy.accountSmtpUserLabelFor(locale),
                icon: Icons.person_outline,
              ),
            ),
            const SizedBox(height: 10),
            _mailTextField(
              context,
              external: isCompactOrScaled,
              controller: _accountSmtpFromCtrl,
              label: AdminUiCopy.accountSmtpFromLabelFor(locale),
              helperText: AdminUiCopy.accountSmtpFromHelperFor(locale),
              icon: Icons.outgoing_mail,
            ),
            const SizedBox(height: 10),
            _mailTextField(
              context,
              external: isCompactOrScaled,
              controller: _accountSmtpPasswordCtrl,
              obscureText: true,
              label: AdminUiCopy.accountSmtpPasswordLabelFor(locale),
              helperText: _accountSmtpPasswordMasked
                  ? AdminUiCopy.configuredLeaveUnchanged(locale)
                  : null,
              icon: Icons.key_outlined,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(AdminUiCopy.accountSmtpUseSslTitleFor(locale)),
              value: _accountSmtpUseSsl,
              onChanged: (v) => setState(() => _accountSmtpUseSsl = v),
            ),
            const SizedBox(height: 16),
            AppSwitchTile(
              icon: Icons.alternate_email_outlined,
              color: Colors.deepPurple,
              value: _reminderEmailEnabled,
              title: AdminUiCopy.reminderEmailEnableTitleFor(locale),
              subtitle: AdminUiCopy.reminderEmailEnableSubtitleFor(locale),
              onChanged: (v) => setState(() => _reminderEmailEnabled = v),
            ),
            const SizedBox(height: 10),
            _adminResponsiveTwoColumn(
              context: context,
              first: _mailTextField(
                context,
                external: isCompactOrScaled,
                controller: _reminderEmailToCtrl,
                label: AdminUiCopy.reminderDefaultRecipientLabelFor(locale),
                helperText: AdminUiCopy.reminderDefaultRecipientHelperFor(
                  locale,
                ),
                icon: Icons.alternate_email,
              ),
              second: _mailTextField(
                context,
                external: isCompactOrScaled,
                controller: _reminderEmailFromCtrl,
                label: AdminUiCopy.reminderSenderLabelFor(locale),
                icon: Icons.outgoing_mail,
              ),
            ),
            const SizedBox(height: 10),
            _mailTextField(
              context,
              external: isCompactOrScaled,
              controller: _reminderSmtpHostCtrl,
              label: AdminUiCopy.reminderSmtpHostLabelFor(locale),
              icon: Icons.dns_outlined,
            ),
            const SizedBox(height: 10),
            _adminResponsiveTwoColumn(
              context: context,
              first: _mailTextField(
                context,
                external: isCompactOrScaled,
                controller: _reminderSmtpPortCtrl,
                keyboardType: TextInputType.number,
                label: AdminUiCopy.reminderSmtpPortLabelFor(locale),
                icon: Icons.numbers_outlined,
              ),
              second: _mailTextField(
                context,
                external: isCompactOrScaled,
                controller: _reminderSmtpUserCtrl,
                label: AdminUiCopy.reminderSmtpUserLabelFor(locale),
                icon: Icons.person_outline,
              ),
            ),
            const SizedBox(height: 10),
            _mailTextField(
              context,
              external: isCompactOrScaled,
              controller: _reminderSmtpPasswordCtrl,
              obscureText: true,
              label: AdminUiCopy.reminderSmtpPasswordLabelFor(locale),
              helperText: _reminderSmtpPasswordMasked
                  ? AdminUiCopy.configuredLeaveUnchanged(locale)
                  : null,
              icon: Icons.key_outlined,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(
                    _saving
                        ? AdminUiCopy.savingEllipsis(locale)
                        : AdminUiCopy.saveConfigBtnFor(locale),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _runningServerBackup ? null : _runServerBackup,
                  icon: _runningServerBackup
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.backup_outlined),
                  label: Text(
                    _runningServerBackup
                        ? AdminUiCopy.backingUpEllipsis(locale)
                        : AdminUiCopy.runBackupNowBtnFor(locale),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _testingReminderEmail ? null : _testReminderEmail,
                  icon: _testingReminderEmail
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.mark_email_read_outlined),
                  label: Text(
                    _testingReminderEmail
                        ? AdminUiCopy.sendingEllipsis(locale)
                        : AdminUiCopy.testReminderEmailBtnFor(locale),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _testingAccountEmail ? null : _testAccountEmail,
                  icon: _testingAccountEmail
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.alternate_email_outlined),
                  label: Text(
                    _testingAccountEmail
                        ? AdminUiCopy.sendingEllipsis(locale)
                        : AdminUiCopy.testAccountEmailBtnFor(locale),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 640,
          child: _buildBackupRecordTabs(
            context,
            theme: theme,
            cs: cs,
            totalKb: totalKb,
            locale: locale,
          ),
        ),
      ],
    );
  }
}

// ====================================================================
// 用户
// ====================================================================

class _UserAction {
  _UserAction(this.authority, this.view, this.allowed) : revision = view.value;
  final AdminActionOrigin authority;
  final ValueListenable<int> view;
  final int revision;
  final bool Function() allowed;
  bool _invalid = false;
  ApiClient get client => authority.client;
  bool isCurrent({bool checkRoute = true}) {
    if (_invalid) return false;
    if (view.value != revision ||
        !allowed() ||
        !authority.isCurrent(checkRoute: checkRoute)) {
      _invalid = true;
      return false;
    }
    return true;
  }
}

class _UserOperation {
  _UserOperation(this.origin);
  final _UserAction origin;
  DialogRoute<bool>? dialog;
}

String _userText(String zh, String en, [AppLocale? locale]) =>
    (locale ?? I18n.current) == AppLocale.zh ? zh : en;

class _UsersTab extends StatefulWidget {
  final AdminApi api;
  final String? selfId;
  final List<String>? selfAdminPermissions;
  final bool isActive;
  final ValueListenable<int> activationRevision;
  const _UsersTab({
    super.key,
    required this.api,
    required this.selfId,
    required this.selfAdminPermissions,
    required this.isActive,
    required this.activationRevision,
  });
  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> {
  static const _onlineRefreshInterval = Duration(seconds: 60);
  final _actionHost = AdminActionHost();

  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _groups = [];
  List<Map<String, dynamic>> _roles = [];
  AdminPage? _page;
  bool _loading = true;
  Object? _error;
  Object? _refreshError;
  _UserAction? _listOrigin;
  Future<void> Function()? _failedLoad;
  List<(Object, String)> _auxiliaryErrors = [];
  String _query = '';
  String _status = '';
  String _sort = 'created_desc';
  int _pageSize = _adminPageSize;
  int _offset = 0;
  int _loadSerial = 0;
  final Set<String> _selectedUserIds = <String>{};
  Timer? _onlineRefreshTimer;
  Object? _backgroundOperation;
  _UserOperation? _writeOperation;
  int? _authorityRevision;
  int? _viewRevision;
  bool _deferredRead = false;
  bool get _backgroundRefreshInFlight => _backgroundOperation != null;
  bool get _busy => _loading || _writeOperation != null;
  final _searchCtrl = TextEditingController();

  bool _canUseAdminPermission(String permission) {
    final permissions = widget.selfAdminPermissions;
    if (permissions == null) return true;
    return !permissions.contains(_adminNoPermission) &&
        (permissions.contains(_adminAllPermission) ||
            permissions.contains(permission));
  }

  bool get _canManageCoins => _canUseAdminPermission('coins');
  bool get _canManageUsers => _canUseAdminPermission('users');
  bool get _canManageGroups => _canUseAdminPermission('groups');
  bool get _canManageRoles => _canUseAdminPermission('roles');
  bool get _canManagePermissions => _canUseAdminPermission('permissions');
  bool get _canReadUsers => _canManageUsers || _canManageCoins;
  bool get _canReadGroupNames => _canManageGroups || _canManageCoins;
  bool get _canReadRoleNames => _canManageRoles;
  bool get _canAssignGroups =>
      _canManageUsers && (_canManageGroups || _canManageCoins);
  bool get _canManageAdminAccess => _canManageRoles || _canManagePermissions;
  bool get _canManageUserAdminAccess =>
      _canManageUsers && _canManageAdminAccess;
  bool get _hasAllAdminPermission {
    final permissions = widget.selfAdminPermissions;
    return permissions == null ||
        (!permissions.contains(_adminNoPermission) &&
            permissions.contains(_adminAllPermission));
  }

  bool _canToggleAdminFor(bool currentAdmin) {
    if (!_canManageUsers) return false;
    return currentAdmin ? _canManageAdminAccess : _hasAllAdminPermission;
  }

  _UserAction _capture({
    Set<String> permissions = const {'users', 'coins'},
    bool Function()? allowed,
  }) {
    _syncAuthority();
    return _UserAction(
      _actionHost.capture(
        client: widget.api.client,
        anyOfPermissions: permissions,
      ),
      widget.activationRevision,
      allowed ?? () => true,
    );
  }

  // Mutable client fields may change without a provider notification. Clear
  // older data before issuing any receipt for the new server/token snapshot.
  void _syncAuthority() {
    final revision = _actionHost.revision;
    if (_authorityRevision == revision) return;
    _authorityRevision = revision;
    _invalidate(clearPrivateData: true);
    _deferLoad();
  }

  bool _current(_UserAction origin, {bool checkRoute = true}) {
    if (!mounted) return false;
    _syncAuthority();
    return widget.isActive && origin.isCurrent(checkRoute: checkRoute);
  }

  bool _operationCurrent(_UserOperation operation) {
    final dialog = operation.dialog;
    return identical(_writeOperation, operation) &&
        _current(operation.origin, checkRoute: dialog == null) &&
        (dialog == null || (dialog.isActive && dialog.isCurrent));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _actionHost.bind(context);
    _viewRevision ??= widget.activationRevision.value;
    final revision = _actionHost.revision;
    if (_authorityRevision == revision) {
      if (_deferredRead) _deferLoad();
      return;
    }
    _authorityRevision = revision;
    _invalidate(clearPrivateData: true);
    _deferLoad();
  }

  void _invalidate({bool clearPrivateData = false}) {
    _loadSerial++;
    _failedLoad = null;
    _backgroundOperation = null;
    _writeOperation = null;
    _loading = false;
    _deferredRead = widget.isActive;
    if (!clearPrivateData) return;
    _users = [];
    _groups = [];
    _roles = [];
    _page = null;
    _listOrigin = null;
    _error = null;
    _refreshError = null;
    _auxiliaryErrors = [];
    _selectedUserIds.clear();
    _query = '';
    _status = '';
    _sort = 'created_desc';
    _offset = 0;
    _pageSize = _adminPageSize;
    _searchCtrl.clear();
  }

  void _deferLoad() {
    if (!widget.isActive) return;
    _startOnlineRefreshTimer();
    final serial = _loadSerial;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || serial != _loadSerial || !_deferredRead) return;
      setState(() {});
      // Do not latch a receipt while an unrelated route covers this page.
      final route = ModalRoute.of(context);
      if ((route != null && !route.isCurrent) ||
          _busy ||
          _backgroundRefreshInFlight) {
        return;
      }
      final origin = _capture();
      if (_current(origin)) {
        _deferredRead = false;
        _load(origin: origin);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void didUpdateWidget(covariant _UsersTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.api.client, widget.api.client) ||
        oldWidget.selfId != widget.selfId) {
      _invalidate(clearPrivateData: true);
      _deferLoad();
      return;
    }
    if (oldWidget.isActive == widget.isActive &&
        _viewRevision == widget.activationRevision.value) {
      return;
    }
    _viewRevision = widget.activationRevision.value;
    _invalidate();
    if (widget.isActive) {
      _deferLoad();
    } else {
      _stopOnlineRefreshTimer();
    }
  }

  void _startOnlineRefreshTimer() {
    if (_onlineRefreshTimer != null) return;
    _onlineRefreshTimer = Timer.periodic(_onlineRefreshInterval, (_) {
      if (!mounted || !widget.isActive || _busy || _backgroundRefreshInFlight) {
        return;
      }
      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent) return;
      final origin = _capture();
      if (!_current(origin)) return;
      final deferred = _deferredRead;
      _deferredRead = false;
      _load(origin: origin, quiet: !deferred, background: !deferred);
    });
  }

  void _stopOnlineRefreshTimer() {
    _onlineRefreshTimer?.cancel();
    _onlineRefreshTimer = null;
  }

  @override
  void dispose() {
    _loadSerial++;
    _writeOperation = null;
    _backgroundOperation = null;
    _stopOnlineRefreshTimer();
    _actionHost.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<bool> _load({
    _UserAction? origin,
    _UserOperation? operation,
    String? query,
    String? status,
    String? sort,
    int? pageSize,
    int? offset,
    bool quiet = false,
    bool background = false,
  }) async {
    final source = origin ?? _capture();
    bool valid() =>
        _current(source) &&
        (operation == null
            ? _writeOperation == null
            : _operationCurrent(operation));
    if (!valid() || (background && (_backgroundRefreshInFlight || _loading))) {
      return false;
    }
    final marker = Object();
    if (background) _backgroundOperation = marker;
    final loadSerial = ++_loadSerial;
    bool current() => valid() && loadSerial == _loadSerial;
    final nextQuery = query ?? _query;
    final nextStatus = status ?? _status;
    final nextSort = sort ?? _sort;
    final nextPageSize = pageSize ?? _pageSize;
    final nextOffset = offset ?? _offset;
    setState(() {
      _query = nextQuery;
      _status = nextStatus;
      _sort = nextSort;
      _pageSize = nextPageSize;
      _offset = nextOffset;
      if (!quiet) _loading = true;
      _error = null;
      _refreshError = null;
    });
    try {
      final errors = <(Object, String)>[];
      final api = AdminApi(source.client);
      final pageFuture = api.listUsersPage(
        query: nextQuery.isEmpty ? null : nextQuery,
        status: _backendStatusFilter(nextStatus),
        online: _onlineFilter(nextStatus),
        sort: nextSort,
        limit: nextPageSize,
        offset: nextOffset,
        isCurrent: current,
      );
      final groupsOrigin = _capture(
        permissions: const {'users', 'groups', 'coins'},
      );
      final rolesOrigin = _capture(permissions: const {'users', 'roles'});
      Future<List<Map<String, dynamic>>> auxiliary(String target) async {
        final receipt = target == 'groups' ? groupsOrigin : rolesOrigin;
        bool allowed() => current() && _current(receipt);
        if (!allowed()) return [];
        try {
          return target == 'groups'
              ? await api.listGroups(isCurrent: allowed)
              : await api.listRoles(isCurrent: allowed);
        } catch (error) {
          if (allowed()) errors.add((error, target));
          return [];
        }
      }

      final results = await Future.wait<dynamic>([
        pageFuture,
        _groups.isEmpty && _canReadGroupNames
            ? auxiliary('groups')
            : Future.value(_groups),
        _roles.isEmpty && _canReadRoleNames
            ? auxiliary('roles')
            : Future.value(_roles),
      ]);
      if (!current()) return false;
      final page = results[0] as AdminPage;
      setState(() {
        _page = page;
        _listOrigin = source;
        _users = page.items;
        _groups = List<Map<String, dynamic>>.from(results[1] as List);
        _roles = List<Map<String, dynamic>>.from(results[2] as List);
        _selectedUserIds.removeWhere(
          (id) => !_users.any((u) => u['user_id'].toString() == id),
        );
        _error = null;
        _failedLoad = null;
        _auxiliaryErrors = errors;
      });
      return true;
    } catch (error) {
      if (current()) {
        setState(() {
          if (quiet && _page != null) {
            _refreshError = error;
          } else {
            _error = error;
            _failedLoad = () async {
              if (loadSerial != _loadSerial || !_current(source) || _busy) {
                return;
              }
              await _load(
                origin: source,
                query: nextQuery,
                status: nextStatus,
                sort: nextSort,
                pageSize: nextPageSize,
                offset: nextOffset,
              );
            };
          }
        });
      }
      return false;
    } finally {
      if (mounted && identical(_backgroundOperation, marker)) {
        _backgroundOperation = null;
      }
      if (mounted && loadSerial == _loadSerial) {
        if (!current() && widget.isActive) {
          _deferredRead = true;
          _deferLoad();
        }
        setState(() => _loading = false);
      }
    }
  }

  void _snack(_UserAction origin, String Function(AppLocale) copy) {
    if (!_current(origin)) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: _AdminFeedbackText(copy)));
  }

  Future<void> _mutate(
    _UserAction rendered,
    Set<String> permissions,
    bool Function() allowed,
    Future<void> Function(_UserOperation) body,
  ) async {
    if (_loading ||
        _writeOperation != null ||
        !_current(rendered) ||
        !allowed()) {
      return;
    }
    final origin = _capture(permissions: permissions, allowed: allowed);
    if (!_current(origin)) return;
    final operation = _UserOperation(origin);
    setState(() => _writeOperation = operation);
    try {
      await body(operation);
    } catch (error) {
      if (_operationCurrent(operation)) {
        _snack(
          origin,
          (locale) => _adminActionErrorMessage(
            error,
            _userText('更新用户', 'Update user', locale),
            locale,
          ),
        );
      }
    } finally {
      if (mounted && identical(_writeOperation, operation)) {
        setState(() => _writeOperation = null);
        if (_deferredRead) _deferLoad();
      }
    }
  }

  Future<bool> _dialog(
    _UserOperation operation,
    Widget Function(BuildContext, StateSetter, bool) builder, {
    List<TextEditingController> controllers = const [],
  }) async {
    if (!_operationCurrent(operation)) return false;
    final route = DialogRoute<bool>(
      context: context,
      builder: (ctx) => ValueListenableBuilder<int>(
        valueListenable: widget.activationRevision,
        builder: (ctx, _, _) => ValueListenableBuilder<AppLocale>(
          valueListenable: I18n.localeListenable,
          builder: (ctx, _, _) {
            ModalRoute.isCurrentOf(ctx);
            ctx.watch<AuthProvider?>();
            ctx.watch<AppLockProvider?>();
            ctx.watch<AppUpdateService?>();
            return StatefulBuilder(
              builder: (ctx, setSt) {
                if (!_operationCurrent(operation)) {
                  return AppDialog(
                    title: Text(_userText('操作已失效', 'Action expired')),
                    content: Text(
                      _userText(
                        '账号、权限或页面已变更。请关闭后重新操作。',
                        'Your account, access or page changed. Close and try again.',
                      ),
                    ),
                    actions: [_actions(ctx, operation, '').first],
                  );
                }
                return builder(ctx, setSt, true);
              },
            );
          },
        ),
      ),
    );
    operation.dialog = route;
    try {
      final saved = await Navigator.of(context).push(route);
      operation.dialog = null;
      return saved == true && _operationCurrent(operation);
    } finally {
      if (identical(operation.dialog, route)) operation.dialog = null;
      await route.completed;
      for (final controller in controllers) {
        controller.dispose();
      }
    }
  }

  List<Widget> _actions(
    BuildContext ctx,
    _UserOperation operation,
    String save,
  ) => [
    TextButton(
      onPressed: () {
        final route = operation.dialog;
        if (ctx.mounted &&
            route?.isActive == true &&
            route?.isCurrent == true) {
          Navigator.of(ctx).pop(false);
        }
      },
      child: Text(AdminUiCopy.cancelFor(I18n.current)),
    ),
    FilledButton(
      onPressed: _operationCurrent(operation)
          ? () {
              if (ctx.mounted && _operationCurrent(operation)) {
                Navigator.of(ctx).pop(true);
              }
            }
          : null,
      child: Text(save),
    ),
  ];

  Future<bool> _confirm(
    _UserOperation operation,
    String Function() title,
    String Function() message,
    String Function() save,
  ) => _dialog(
    operation,
    (ctx, _, _) => AppDialog(
      title: Text(title()),
      icon: const Icon(Icons.info_outline),
      content: Text(message()),
      actions: _actions(ctx, operation, save()),
    ),
  );

  Future<void> _refreshWritten(
    _UserOperation operation,
    String Function(AppLocale) success, {
    int? offset,
  }) async {
    if (!_operationCurrent(operation)) return;
    final refreshed = await _load(
      origin: _capture(),
      operation: operation,
      offset: offset,
      quiet: true,
    );
    _snack(
      operation.origin,
      (locale) => refreshed
          ? success(locale)
          : _userText(
              '${success(locale)}，但列表刷新失败。请手动刷新。',
              '${success(locale)} List refresh failed. Refresh manually.',
              locale,
            ),
    );
  }

  String _adminEntityName(
    List<Map<String, dynamic>> items,
    String id,
    String fallback,
  ) {
    if (id.isEmpty) return fallback;
    for (final item in items) {
      if (item['id'].toString() == id) {
        final name = (item['name'] ?? '').toString();
        return name.isEmpty ? id : name;
      }
    }
    return id;
  }

  List<DropdownMenuItem<String>> _adminEntityItems(
    List<Map<String, dynamic>> items,
    String currentId,
    String currentFallback, {
    bool activeOnly = false,
  }) {
    final seen = <String>{};
    final result = <DropdownMenuItem<String>>[];
    if (currentId.isNotEmpty) {
      seen.add(currentId);
      final current = items.cast<Map<String, dynamic>?>().firstWhere(
        (item) => item?['id'].toString() == currentId,
        orElse: () => null,
      );
      final isInactive = current?['is_active'] == false;
      result.add(
        DropdownMenuItem(
          value: currentId,
          child: Text(
            '${_adminEntityName(items, currentId, currentFallback)}${isInactive ? _userText(' · 停用', ' · Inactive') : ''}',
          ),
        ),
      );
    }
    for (final item in items) {
      final id = (item['id'] ?? '').toString();
      if (id.isEmpty || seen.contains(id)) continue;
      if (activeOnly && item['is_active'] == false) continue;
      seen.add(id);
      final name = (item['name'] ?? '').toString();
      final count = _adminIntValue(item['user_count']);
      result.add(
        DropdownMenuItem(
          value: id,
          child: Text(
            _userText(
              '${name.isEmpty ? id : name} · $count 人',
              '${name.isEmpty ? id : name} · $count users',
            ),
          ),
        ),
      );
    }
    return result;
  }

  List<DropdownMenuItem<String>> _roleEntityItems(
    String currentId,
    String currentFallback, {
    bool activeOnly = false,
  }) {
    final roles = _hasAllAdminPermission
        ? _roles
        : _roles
              .where((role) => (role['id'] ?? '').toString() != 'role_admin')
              .toList(growable: false);
    return _adminEntityItems(
      roles,
      currentId,
      currentFallback,
      activeOnly: activeOnly,
    );
  }

  void _applySearch(_UserAction origin) {
    if (!_current(origin) || _busy) return;
    _load(origin: origin, query: _searchCtrl.text.trim(), offset: 0);
  }

  void _applyStatus(_UserAction origin, String status) {
    if (!_current(origin) || _busy) return;
    _load(origin: origin, status: status, offset: 0);
  }

  void _applySort(_UserAction origin, String sort) {
    if (!_current(origin) || _busy) return;
    _load(origin: origin, sort: sort, offset: 0);
  }

  void _jumpToPage(_UserAction origin, int pageNumber) {
    if (!_current(origin) || _busy) return;
    final page = pageNumber < 1 ? 1 : pageNumber;
    _load(origin: origin, offset: (page - 1) * _pageSize);
  }

  bool? _onlineFilter(String status) {
    if (status == 'online') return true;
    if (status == 'offline') return false;
    return null;
  }

  String? _backendStatusFilter(String status) {
    if (status.isEmpty || status == 'online' || status == 'offline') {
      return null;
    }
    return status;
  }

  Future<void> _createUser(_UserAction rendered) => _mutate(
    rendered,
    const {'users'},
    () => _canManageUsers,
    (operation) async {
      if ((_canAssignGroups && _groups.isEmpty) ||
          (_canManageRoles && _roles.isEmpty)) {
        await _load(operation: operation, quiet: true);
      }
      if (!_operationCurrent(operation)) return;
      final usernameCtrl = TextEditingController();
      final passwordCtrl = TextEditingController();
      final displayNameCtrl = TextEditingController();
      final emailCtrl = TextEditingController();
      var username = '', password = '', displayName = '', email = '';
      final roles = _hasAllAdminPermission
          ? _roles
          : _roles.where((r) => r['id'] != 'role_admin').toList();
      var groupId = _groups.any((g) => g['id'] == 'group_default')
          ? 'group_default'
          : (_groups.isEmpty ? '' : _groups.first['id'].toString());
      var roleId = roles.any((r) => r['id'] == 'role_user')
          ? 'role_user'
          : (roles.isEmpty ? '' : roles.first['id'].toString());
      var admin = false, disabled = false;
      final saved = await _dialog(
        operation,
        (ctx, setSt, canEdit) => AppDialog(
          title: Text(_userText('新增用户', 'Create user')),
          icon: const Icon(Icons.person_add_alt_1_outlined),
          content: _adminDialogForm(
            children: [
              TextField(
                controller: usernameCtrl,
                enabled: canEdit,
                decoration: InputDecoration(
                  labelText: _userText('用户名', 'Username'),
                ),
                textInputAction: TextInputAction.next,
                onChanged: (v) => username = v,
              ),
              TextField(
                controller: passwordCtrl,
                enabled: canEdit,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: _userText('初始密码', 'Initial password'),
                  helperText: _userText(
                    '留空时由服务器生成随机密码',
                    'Leave blank to generate a password',
                  ),
                ),
                textInputAction: TextInputAction.next,
                onChanged: (v) => password = v,
              ),
              TextField(
                controller: displayNameCtrl,
                enabled: canEdit,
                decoration: InputDecoration(
                  labelText: _userText('昵称 (可选)', 'Display name (optional)'),
                ),
                textInputAction: TextInputAction.next,
                onChanged: (v) => displayName = v,
              ),
              TextField(
                controller: emailCtrl,
                enabled: canEdit,
                decoration: InputDecoration(
                  labelText: _userText('邮箱 (可选)', 'Email (optional)'),
                ),
                keyboardType: TextInputType.emailAddress,
                onChanged: (v) => email = v,
              ),
              if (_canAssignGroups && _groups.isNotEmpty)
                AppDropdownField<String>(
                  initialValue: groupId,
                  labelText: _userText('用户组', 'Group'),
                  items: _adminEntityItems(
                    _groups,
                    groupId,
                    _userText('默认组', 'Default group'),
                    activeOnly: true,
                  ),
                  onChanged: (v) {
                    if (v != null && _operationCurrent(operation)) {
                      setSt(() => groupId = v);
                    }
                  },
                ),
              if (_canManageRoles && roles.isNotEmpty)
                AppDropdownField<String>(
                  initialValue: roleId,
                  labelText: _userText('角色', 'Role'),
                  items: _adminEntityItems(
                    roles,
                    roleId,
                    _userText('普通角色', 'Standard role'),
                    activeOnly: true,
                  ),
                  onChanged: (v) {
                    if (v != null && _operationCurrent(operation)) {
                      setSt(() => roleId = v);
                    }
                  },
                ),
              if (_hasAllAdminPermission)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: admin,
                  title: Text(_userText('管理员账号', 'Administrator account')),
                  onChanged: canEdit
                      ? (v) => setSt(() {
                          admin = v;
                          if (v &&
                              roleId == 'role_user' &&
                              _roles.any((r) => r['id'] == 'role_admin')) {
                            roleId = 'role_admin';
                          }
                          if (!v && roleId == 'role_admin') {
                            roleId = 'role_user';
                          }
                        })
                      : null,
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: disabled,
                title: Text(_userText('创建后先禁用', 'Create as disabled')),
                onChanged: canEdit ? (v) => setSt(() => disabled = v) : null,
              ),
            ],
          ),
          actions: _actions(ctx, operation, _userText('创建', 'Create')),
        ),
        controllers: [usernameCtrl, passwordCtrl, displayNameCtrl, emailCtrl],
      );
      if (!saved) return;
      if (username.trim().isEmpty) {
        _snack(
          operation.origin,
          (l) => _userText('请填写用户名', 'Enter a username', l),
        );
        return;
      }
      await AdminApi(operation.origin.client).createUser(
        username: username.trim(),
        password: password,
        displayName: displayName,
        email: email,
        groupId: _canAssignGroups ? groupId : null,
        roleId: _canManageRoles ? roleId : null,
        isAdmin: _hasAllAdminPermission && admin,
        isDisabled: disabled,
        isCurrent: () => _operationCurrent(operation),
      );
      await _refreshWritten(
        operation,
        (l) => _userText('用户已创建', 'User created.', l),
        offset: 0,
      );
    },
  );

  Future<void> _toggleAdmin(_UserAction rendered, Map<String, dynamic> u) =>
      _mutate(
        rendered,
        const {'users'},
        () => _canToggleAdminFor(u['is_admin'] == true),
        (operation) async {
          final becomeAdmin = u['is_admin'] != true;
          if (!becomeAdmin && u['user_id'].toString() == widget.selfId) return;
          final saved = await _confirm(
            operation,
            () => _userText(
              becomeAdmin ? '授予管理员身份？' : '撤销管理员身份？',
              becomeAdmin
                  ? 'Grant administrator access?'
                  : 'Revoke administrator access?',
            ),
            () => _userText(
              '将更新 ${u['username']} 的管理员身份。',
              'This updates administrator access for ${u['username']}.',
            ),
            () => _userText('确认', 'Confirm'),
          );
          if (!saved) return;
          await AdminApi(operation.origin.client).updateUser(
            u['user_id'].toString(),
            isAdmin: becomeAdmin,
            isCurrent: () => _operationCurrent(operation),
          );
          await _refreshWritten(
            operation,
            (l) => _userText('管理员身份已更新', 'Administrator access updated.', l),
          );
        },
      );

  Future<void> _toggleDisable(_UserAction rendered, Map<String, dynamic> u) =>
      _mutate(rendered, const {'users'}, () => _canManageUsers, (
        operation,
      ) async {
        if (u['user_id'].toString() == widget.selfId) return;
        final disable = u['is_disabled'] != true;
        if (!await _confirm(
          operation,
          () => _userText(
            disable ? '禁用账号？' : '恢复账号？',
            disable ? 'Disable account?' : 'Restore account?',
          ),
          () => _userText(
            disable ? '禁用后该账号需要重新登录。' : '恢复后该账号可以登录。',
            disable
                ? 'The account will need to sign in again.'
                : 'The account will be able to sign in.',
          ),
          () =>
              _userText(disable ? '禁用' : '恢复', disable ? 'Disable' : 'Restore'),
        )) {
          return;
        }
        await AdminApi(operation.origin.client).updateUser(
          u['user_id'].toString(),
          isDisabled: disable,
          isCurrent: () => _operationCurrent(operation),
        );
        await _refreshWritten(
          operation,
          (l) => _userText('账号状态已更新', 'Account status updated.', l),
        );
      });

  Future<void> _exportUsersCsv(_UserAction rendered) => _mutate(
    rendered,
    const {'users'},
    () => _canManageUsers,
    (operation) async {
      final query = _query, status = _status, sort = _sort;
      final csv = await AdminApi(operation.origin.client).exportUsersCsv(
        query: query.isEmpty ? null : query,
        status: _backendStatusFilter(status),
        online: _onlineFilter(status),
        sort: sort,
        isCurrent: () => _operationCurrent(operation),
      );
      if (!_operationCurrent(operation)) return;
      final dir = await getTemporaryDirectory();
      if (!_operationCurrent(operation)) return;
      final file = File(
        '${dir.path}/duoyi_users_${DateTime.now().millisecondsSinceEpoch}.csv',
      );
      await file.writeAsString(csv, flush: true);
      if (!_operationCurrent(operation)) return;
      await Clipboard.setData(ClipboardData(text: file.path));
      if (!_operationCurrent(operation)) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: _userText('多仪管理员用户导出', 'Duoyi administrator user export'),
          subject: _userText('多仪用户 CSV', 'Duoyi users CSV'),
        ),
      );
      if (!_operationCurrent(operation)) return;
      _snack(
        operation.origin,
        (l) => _userText(
          '用户 CSV 已导出，路径已复制：${file.path}',
          'Users exported. File path copied: ${file.path}',
          l,
        ),
      );
    },
  );

  List<String> get _selectableCurrentPageUserIds {
    if (!_canManageUsers) return const [];
    return _users
        .map((u) => u['user_id'].toString())
        .where((id) => id.isNotEmpty && id != widget.selfId)
        .toList();
  }

  List<String> get _selectedCurrentPageUserIds =>
      _selectableCurrentPageUserIds.where(_selectedUserIds.contains).toList();

  void _toggleUserSelection(_UserAction origin, String userId, bool selected) {
    if (!_current(origin) ||
        _busy ||
        !_canManageUsers ||
        !_selectableCurrentPageUserIds.contains(userId)) {
      return;
    }
    setState(() {
      if (selected) {
        _selectedUserIds.add(userId);
      } else {
        _selectedUserIds.remove(userId);
      }
    });
  }

  void _toggleCurrentPageSelection(_UserAction origin, bool selected) {
    if (!_current(origin) || _busy || !_canManageUsers) return;
    setState(() {
      if (selected) {
        _selectedUserIds.addAll(_selectableCurrentPageUserIds);
      } else {
        _selectedUserIds.removeAll(_selectableCurrentPageUserIds);
      }
    });
  }

  Future<void> _bulkSetDisabled(
    _UserAction rendered,
    bool disabled,
  ) => _mutate(rendered, const {'users'}, () => _canManageUsers, (
    operation,
  ) async {
    final ids = List<String>.unmodifiable(_selectedCurrentPageUserIds);
    if (ids.isEmpty) return;
    if (!await _confirm(
      operation,
      () => _userText(
        disabled ? '批量禁用账号？' : '批量恢复账号？',
        disabled ? 'Disable selected accounts?' : 'Restore selected accounts?',
      ),
      () => _userText(
        '将${disabled ? '禁用' : '恢复'}当前页已选的 ${ids.length} 个账号。',
        '${disabled ? 'Disable' : 'Restore'} ${ids.length} selected accounts on this page.',
      ),
      () => _userText(disabled ? '禁用' : '恢复', disabled ? 'Disable' : 'Restore'),
    )) {
      return;
    }
    await AdminApi(operation.origin.client).bulkUpdateUserStatus(
      userIds: ids,
      isDisabled: disabled,
      isCurrent: () => _operationCurrent(operation),
    );
    if (!_operationCurrent(operation)) return;
    _selectedUserIds.removeAll(ids);
    await _refreshWritten(
      operation,
      (l) => _userText(
        '已${disabled ? '禁用' : '恢复'} ${ids.length} 个账号',
        '${ids.length} accounts ${disabled ? 'disabled' : 'restored'}.',
        l,
      ),
    );
  });

  Future<void> _resetPassword(_UserAction rendered, Map<String, dynamic> u) =>
      _mutate(rendered, const {'users'}, () => _canManageUsers, (
        operation,
      ) async {
        final ctrl = TextEditingController();
        var password = '';
        if (!await _dialog(
          operation,
          (ctx, _, canEdit) => AppDialog(
            title: Text(
              _userText(
                '重置 ${u['username']} 的密码',
                'Reset password for ${u['username']}',
              ),
            ),
            icon: const Icon(Icons.lock_reset_outlined),
            content: _adminDialogForm(
              maxWidth: 420,
              children: [
                TextField(
                  controller: ctrl,
                  enabled: canEdit,
                  obscureText: true,
                  onChanged: (v) => password = v,
                  decoration: InputDecoration(
                    labelText: _userText('新密码', 'New password'),
                    helperText: _userText(
                      '提交后该用户需要使用新密码重新登录',
                      'The user must sign in again with the new password',
                    ),
                  ),
                ),
              ],
            ),
            actions: _actions(ctx, operation, _userText('提交', 'Submit')),
          ),
          controllers: [ctrl],
        )) {
          return;
        }
        if (password.trim().isEmpty) {
          _snack(
            operation.origin,
            (l) => _userText('请填写新密码', 'Enter a new password', l),
          );
          return;
        }
        await AdminApi(operation.origin.client).updateUser(
          u['user_id'].toString(),
          newPassword: password.trim(),
          isCurrent: () => _operationCurrent(operation),
        );
        _snack(
          operation.origin,
          (l) => _userText(
            '密码已重置，该用户需重新登录',
            'Password reset. The user must sign in again.',
            l,
          ),
        );
      });

  Future<void> _editAdminPermissions(
    _UserAction rendered,
    Map<String, dynamic> u,
  ) => _mutate(rendered, const {'users'}, () => _canManageUserAdminAccess, (
    operation,
  ) async {
    final userId = u['user_id'].toString(), username = u['username'].toString();
    final isAdmin = u['is_admin'] == true;
    if (!isAdmin &&
        !await _confirm(
          operation,
          () => _userText('授予管理员身份？', 'Grant administrator access?'),
          () => _userText(
            '设置管理权限前需要先将“$username”设为管理员。',
            'To set permissions, first grant administrator access to $username.',
          ),
          () => _userText('授予', 'Grant'),
        )) {
      return;
    }
    var selected = _adminUserPermissions(
      u['admin_permissions'],
      isAdmin: isAdmin,
    ).toSet();
    if (selected.contains(_adminAllPermission)) {
      selected = _adminAllPermissionKeys();
    }
    if (!await _dialog(
      operation,
      (ctx, setSt, canEdit) => AppDialog(
        title: Text(
          _userText('设置 $username 的管理权限', 'Set permissions for $username'),
        ),
        icon: const Icon(Icons.admin_panel_settings_outlined),
        content: _adminDialogForm(
          maxWidth: 520,
          children: [
            IgnorePointer(
              ignoring: !canEdit,
              child: _adminPermissionChecklist(
                selected: selected,
                onChanged: (next) {
                  if (_operationCurrent(operation)) {
                    setSt(() => selected = next);
                  }
                },
                locale: I18n.current,
              ),
            ),
          ],
        ),
        actions: _actions(
          ctx,
          operation,
          _userText('保存权限', 'Save permissions'),
        ),
      ),
    )) {
      return;
    }
    final permissions = selected.isEmpty
        ? const [_adminNoPermission]
        : (_adminHasAllPermissions(selected) && _hasAllAdminPermission
              ? const [_adminAllPermission]
              : selected.toList());
    final existingRoleId = (u['role_id'] ?? '').toString();
    final roleIdForPromotion =
        existingRoleId.isNotEmpty &&
            (existingRoleId != 'role_admin' || _hasAllAdminPermission)
        ? existingRoleId
        : 'role_user';
    await AdminApi(operation.origin.client).updateUser(
      userId,
      isAdmin: isAdmin ? null : true,
      roleId: isAdmin ? null : roleIdForPromotion,
      adminPermissions: permissions,
      isCurrent: () => _operationCurrent(operation),
    );
    await _refreshWritten(
      operation,
      (l) => _userText('管理权限已更新', 'Permissions updated.', l),
    );
  });

  Future<void> _editUserGroupRole(
    _UserAction rendered,
    Map<String, dynamic> u,
  ) => _mutate(
    rendered,
    const {'users'},
    () => _canManageUsers && (_canAssignGroups || _canManageRoles),
    (operation) async {
      if ((_canAssignGroups && _groups.isEmpty) ||
          (_canManageRoles && _roles.isEmpty)) {
        await _load(operation: operation, quiet: true);
      }
      if (!_operationCurrent(operation)) return;
      var groupId = (u['group_id'] ?? 'group_default').toString();
      var roleId =
          (u['role_id'] ?? (u['is_admin'] == true ? 'role_admin' : 'role_user'))
              .toString();
      final canEditRole =
          _canManageRoles && (_hasAllAdminPermission || roleId != 'role_admin');
      if (!_canAssignGroups && !canEditRole) return;
      if (!await _dialog(
        operation,
        (ctx, setSt, canEdit) => AppDialog(
          title: Text(
            _userText(
              '调整 ${u['username']} 的用户组与角色',
              'Set group and role for ${u['username']}',
            ),
          ),
          icon: const Icon(Icons.manage_accounts_outlined),
          content: _adminDialogForm(
            maxWidth: 430,
            children: [
              if (_canAssignGroups)
                AppDropdownField<String>(
                  initialValue: groupId,
                  labelText: _userText('用户组', 'Group'),
                  items: _adminEntityItems(
                    _groups,
                    groupId,
                    _userText('当前用户组', 'Current group'),
                    activeOnly: true,
                  ),
                  onChanged: (v) {
                    if (v != null && _operationCurrent(operation)) {
                      setSt(() => groupId = v);
                    }
                  },
                ),
              if (canEditRole)
                AppDropdownField<String>(
                  initialValue: roleId,
                  labelText: _userText('管理员角色', 'Administrator role'),
                  items: _roleEntityItems(
                    roleId,
                    _userText('当前角色', 'Current role'),
                    activeOnly: true,
                  ),
                  onChanged: (v) {
                    if (v != null && _operationCurrent(operation)) {
                      setSt(() => roleId = v);
                    }
                  },
                ),
            ],
          ),
          actions: _actions(ctx, operation, _userText('保存', 'Save')),
        ),
      )) {
        return;
      }
      await AdminApi(operation.origin.client).updateUser(
        u['user_id'].toString(),
        groupId: _canAssignGroups ? groupId : null,
        roleId: canEditRole ? roleId : null,
        isCurrent: () => _operationCurrent(operation),
      );
      await _refreshWritten(
        operation,
        (l) => _userText('用户组与角色已更新', 'Group and role updated.', l),
      );
    },
  );

  Future<void> _adjustCoins(
    _UserAction rendered,
    Map<String, dynamic> u,
  ) => _mutate(rendered, const {'coins'}, () => _canManageCoins, (
    operation,
  ) async {
    final deltaCtrl = TextEditingController(),
        reasonCtrl = TextEditingController();
    var deltaText = '', reason = '';
    final balance = _adminIntValue(u['coin_balance']),
        lifetime = _adminIntValue(u['lifetime_coins']);
    if (!await _dialog(
      operation,
      (ctx, _, canEdit) => AppDialog(
        title: Text(
          _userText(
            '调整 ${u['username']} 的时光币',
            'Adjust coins for ${u['username']}',
          ),
        ),
        icon: const Icon(Icons.toll_outlined),
        content: _adminDialogForm(
          maxWidth: 430,
          children: [
            Text(
              _userText(
                '当前 $balance · 累计 $lifetime',
                'Balance $balance · Lifetime $lifetime',
              ),
            ),
            TextField(
              controller: deltaCtrl,
              enabled: canEdit,
              onChanged: (v) => deltaText = v,
              decoration: InputDecoration(
                labelText: _userText('调整数量', 'Adjustment'),
                helperText: _userText(
                  '正数增加，负数扣减',
                  'Positive to add, negative to subtract',
                ),
              ),
              keyboardType: const TextInputType.numberWithOptions(signed: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^-?\d*')),
              ],
            ),
            TextField(
              controller: reasonCtrl,
              enabled: canEdit,
              maxLines: 2,
              onChanged: (v) => reason = v,
              decoration: InputDecoration(
                labelText: _userText('原因 (可选)', 'Reason (optional)'),
                helperText: _userText(
                  '会写入管理员操作记录',
                  'Recorded in the administrator audit log',
                ),
              ),
            ),
          ],
        ),
        actions: _actions(
          ctx,
          operation,
          _userText('提交调整', 'Apply adjustment'),
        ),
      ),
      controllers: [deltaCtrl, reasonCtrl],
    )) {
      return;
    }
    final delta = int.tryParse(deltaText.trim()) ?? 0;
    if (delta == 0) {
      _snack(
        operation.origin,
        (l) => _userText('调整数量不能为 0', 'Adjustment must be nonzero', l),
      );
      return;
    }
    final adjusted = await AdminApi(operation.origin.client).adjustUserCoins(
      u['user_id'].toString(),
      delta: delta,
      reason: reason,
      isCurrent: () => _operationCurrent(operation),
    );
    if (!_operationCurrent(operation)) return;
    for (final item in _users) {
      if (item['user_id'] == u['user_id']) {
        item['coin_balance'] = adjusted['balance'];
        item['lifetime_coins'] = adjusted['lifetime'];
      }
    }
    await _refreshWritten(
      operation,
      (l) => _userText('时光币已调整', 'Coins adjusted.', l),
    );
  });

  Future<void> _delete(
    _UserAction rendered,
    Map<String, dynamic> u,
  ) => _mutate(rendered, const {'users'}, () => _canManageUsers, (
    operation,
  ) async {
    if (u['user_id'].toString() == widget.selfId) return;
    final offset = _offsetAfterAdminDelete(
      offset: _offset,
      itemCount: _users.length,
      pageSize: _pageSize,
    );
    if (!await _confirm(
      operation,
      () => _userText('删除 ${u['username']} ?', 'Delete ${u['username']}?'),
      () => _userText(
        '会同时删除其所有同步数据与反馈，不可恢复',
        'All synced data and feedback will also be deleted. This cannot be undone.',
      ),
      () => _userText('删除', 'Delete'),
    )) {
      return;
    }
    await AdminApi(operation.origin.client).deleteUser(
      u['user_id'].toString(),
      isCurrent: () => _operationCurrent(operation),
    );
    await _refreshWritten(
      operation,
      (l) => _userText('用户已删除', 'User deleted.', l),
      offset: offset,
    );
  });

  String _formatServerTime(dynamic raw, String? pattern) {
    final text = raw?.toString() ?? '';
    if (text.isEmpty || text == 'null') return '-';
    var normalized = text.contains('T') ? text : text.replaceFirst(' ', 'T');
    final hasTimezone = RegExp(r'(Z|[+-]\d\d:?\d\d)$').hasMatch(normalized);
    if (!hasTimezone) normalized = '${normalized}Z';
    final parsed = DateTime.tryParse(normalized);
    if (parsed == null) return text;
    final local = parsed.toLocal();
    return I18nDateFormat.fullDateTime(local, pattern: pattern);
  }

  String _formatLastLogin(dynamic raw, String? pattern) {
    final formatted = _formatServerTime(raw, pattern);
    return formatted == '-' ? _userText('从未登录', 'Never signed in') : formatted;
  }

  String _formatLastActive(dynamic raw, String? pattern) {
    final formatted = _formatServerTime(raw, pattern);
    return formatted == '-' ? _userText('从未活跃', 'Never active') : formatted;
  }

  Future<void> _showUserDetails(
    _UserAction rendered,
    Map<String, dynamic> u,
  ) => _mutate(rendered, const {'users', 'coins'}, () => _canReadUsers, (
    operation,
  ) async {
    final userId = u['user_id'].toString();
    final admin = u['is_admin'] == true, disabled = u['is_disabled'] == true;
    final online = u['online'] == true,
        emailVerified = u['email_verified'] == true;
    final email = (u['email'] ?? '').toString();
    final displayName = (u['display_name'] ?? '').toString();
    final username = (u['username'] ?? '').toString();
    final groupId = (u['group_id'] ?? 'group_default').toString();
    final roleId = (u['role_id'] ?? (admin ? 'role_admin' : 'role_user'))
        .toString();
    final permissions = _adminUserPermissions(
      u['admin_permissions'],
      isAdmin: admin,
    );
    await _dialog(operation, (ctx, _, _) {
      final pattern = AppDateFormat.patternOf(ctx);
      final lines = [
        '${_userText('用户名', 'Username')}: ${username.isEmpty ? '-' : username}',
        '${_userText('用户 ID', 'User ID')}: $userId',
        '${_userText('昵称', 'Display name')}: ${displayName.isEmpty ? '-' : displayName}',
        '${_userText('邮箱', 'Email')}: ${email.isEmpty ? _userText('未绑定邮箱', 'No email') : '$email (${emailVerified ? _userText('已验证', 'Verified') : _userText('未验证', 'Unverified')})'}',
        '${_userText('账号状态', 'Account status')}: ${disabled ? _userText('已禁用', 'Disabled') : _userText('可登录', 'Enabled')} · ${online ? _userText('在线', 'Online') : _userText('离线', 'Offline')}',
        '${_userText('管理员', 'Administrator')}: ${admin ? _userText('是', 'Yes') : _userText('否', 'No')}',
        '${_userText('管理权限', 'Admin permissions')}: ${_adminPermissionsLabel(permissions, isAdmin: admin, locale: I18n.current)}',
        '${_userText('用户组', 'Group')}: ${_adminEntityName(_groups, groupId, _userText('默认组', 'Default group'))}',
        '${_userText('角色', 'Role')}: ${_adminEntityName(_roles, roleId, _userText('普通角色', 'Standard role'))}',
        '${_userText('注册时间', 'Registered')}: ${_formatServerTime(u['created_at'], pattern)}',
        '${_userText('最近登录', 'Last sign in')}: ${_formatLastLogin(u['last_login_at'], pattern)}',
        '${_userText('最近活跃', 'Last active')}: ${_formatLastActive(u['last_active_at'], pattern)}',
        '${_userText('反馈数', 'Feedback count')}: ${u['feedback_count'] ?? '-'}',
        '${_userText('当前排序', 'Sort order')}: ${_adminUserSortLabel(_sort)}',
        '${_userText('时光币', 'Coins')}: ${_adminIntValueOrDash(u['coin_balance'])}',
        '${_userText('累计时光币', 'Lifetime coins')}: ${_adminIntValueOrDash(u['lifetime_coins'])}',
      ];
      return AppDialog(
        title: Text(_userText('用户详情', 'User details')),
        icon: const Icon(Icons.person_search_outlined),
        content: SingleChildScrollView(child: SelectableText(lines.join('\n'))),
        actions: [
          TextButton(
            onPressed: () {
              final route = operation.dialog;
              if (ctx.mounted &&
                  route?.isActive == true &&
                  route?.isCurrent == true) {
                Navigator.of(ctx).pop(false);
              }
            },
            child: Text(_userText('关闭', 'Close')),
          ),
        ],
      );
    });
  });

  PopupMenuButton<String> _userActionMenu(
    BuildContext context,
    Map<String, dynamic> user, {
    required _UserAction origin,
    required bool admin,
    required bool disabled,
    required bool isSelf,
  }) {
    final u = Map<String, dynamic>.unmodifiable(user);
    PopupMenuItem<String> item(
      String key,
      String zh,
      String en, {
      bool enabled = true,
      Color? color,
    }) => PopupMenuItem(
      value: key,
      enabled: enabled,
      child: ValueListenableBuilder<AppLocale>(
        valueListenable: I18n.localeListenable,
        builder: (ctx, locale, _) =>
            AppSecondaryMenuText(_userText(zh, en, locale), color: color),
      ),
    );
    return PopupMenuButton<String>(
      tooltip: _userText('账号操作', 'Account actions'),
      enabled: !_busy,
      onSelected: (action) async {
        if (!_current(origin)) return;
        switch (action) {
          case 'details':
            await _showUserDetails(origin, u);
          case 'admin':
            await _toggleAdmin(origin, u);
          case 'permissions':
            await _editAdminPermissions(origin, u);
          case 'group_role':
            await _editUserGroupRole(origin, u);
          case 'coins':
            await _adjustCoins(origin, u);
          case 'disable':
            await _toggleDisable(origin, u);
          case 'reset':
            await _resetPassword(origin, u);
          case 'delete':
            await _delete(origin, u);
          case 'copy_id':
            await _mutate(
              origin,
              const {'users', 'coins'},
              () => _canReadUsers,
              (operation) async {
                if (!_operationCurrent(operation)) return;
                await Clipboard.setData(
                  ClipboardData(text: u['user_id'].toString()),
                );
                if (_operationCurrent(operation)) {
                  _snack(
                    operation.origin,
                    (l) => _userText('用户 ID 已复制', 'User ID copied', l),
                  );
                }
              },
            );
        }
      },
      itemBuilder: (ctx) => [
        item('details', '查看详情', 'View details'),
        if (_canToggleAdminFor(admin) && !(admin && isSelf))
          item(
            'admin',
            admin ? '撤销管理员权限' : '授予管理员权限',
            admin
                ? 'Revoke administrator access'
                : 'Grant administrator access',
          ),
        item(
          'permissions',
          '设置管理权限',
          'Set admin permissions',
          enabled: _canManageUserAdminAccess,
        ),
        item(
          'group_role',
          '设置用户组/角色',
          'Set group / role',
          enabled: _canManageUsers && (_canAssignGroups || _canManageRoles),
        ),
        item('coins', '调整时光币', 'Adjust coins', enabled: _canManageCoins),
        if (_canManageUsers && !isSelf)
          item(
            'disable',
            disabled ? '恢复账号登录' : '禁用账号登录',
            disabled ? 'Restore account' : 'Disable account',
          ),
        if (_canManageUsers) item('reset', '重置登录密码', 'Reset password'),
        item('copy_id', '复制用户 ID', 'Copy user ID'),
        if (_canManageUsers && !isSelf)
          item(
            'delete',
            '删除账号与数据',
            'Delete account and data',
            color: Theme.of(ctx).colorScheme.error,
          ),
      ],
    );
  }

  Widget _buildUserListItem(BuildContext itemContext, Map<String, dynamic> u) {
    final origin = _listOrigin;
    if (origin == null) return const SizedBox.shrink();
    final snapshot = Map<String, dynamic>.unmodifiable(u);
    final pattern = AppDateFormat.patternOf(itemContext);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final userId = u['user_id'].toString();
    final isSelf = userId == widget.selfId;
    final disabled = u['is_disabled'] == true;
    final admin = u['is_admin'] == true;
    final online = u['online'] == true;
    final permissions = _adminUserPermissions(
      u['admin_permissions'],
      isAdmin: admin,
    );
    final rawCoinBalance = u['coin_balance'];
    final rawLifetimeCoins = u['lifetime_coins'];
    final coinBalance = _adminIntValue(rawCoinBalance);
    final lifetimeCoins = _adminIntValue(rawLifetimeCoins);
    final canSelectForBulk = _canManageUsers;
    final selected = canSelectForBulk && _selectedUserIds.contains(userId);
    final registeredAt = _formatServerTime(u['created_at'], pattern);
    final lastLoginAt = _formatLastLogin(u['last_login_at'], pattern);
    final lastActiveAt = _formatLastActive(u['last_active_at'], pattern);
    final email = (u['email'] ?? '').toString();
    final emailVerified = u['email_verified'] == true;
    final displayName = (u['display_name'] ?? '').toString();
    final username = u['username'].toString();
    final groupId = (u['group_id'] ?? 'group_default').toString();
    final roleId = (u['role_id'] ?? (admin ? 'role_admin' : 'role_user'))
        .toString();
    final groupName = _adminEntityName(
      _groups,
      groupId,
      _userText('默认组', 'Default group'),
    );
    final roleName = _adminEntityName(
      _roles,
      roleId,
      _userText('普通角色', 'Standard role'),
    );
    final actionMenu = _userActionMenu(
      context,
      u,
      origin: origin,
      admin: admin,
      disabled: disabled,
      isSelf: isSelf,
    );
    final statusBadges = <Widget>[
      AppStatusBadge(
        label: online ? _userText('在线', 'Online') : _userText('离线', 'Offline'),
        color: online ? Colors.green : Colors.grey,
        icon: online ? Icons.circle : Icons.radio_button_unchecked,
        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      ),
      if (admin)
        AppStatusBadge(
          label: _userText('管理员', 'Administrator'),
          color: Colors.deepOrange,
        ),
      if (admin && !permissions.contains(_adminAllPermission))
        AppStatusBadge(
          label: _userText('细分权限', 'Limited permissions'),
          color: Colors.indigo,
        ),
      if (disabled)
        AppStatusBadge(
          label: _userText('已禁用', 'Disabled'),
          color: Theme.of(context).colorScheme.error,
        ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 980) {
          final subtleText = appSecondaryControlLabelStyle(
            context,
          ).copyWith(color: cs.onSurface.withValues(alpha: 0.62));
          final mainText = appSecondaryMenuItemTextStyle(context).copyWith(
            color: cs.onSurface,
            decoration: disabled ? TextDecoration.lineThrough : null,
          );
          return AppSurfaceCard(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            borderRadius: BorderRadius.circular(9),
            border: _adminSubtleListBorder(context),
            onTap: () => _showUserDetails(origin, snapshot),
            child: Row(
              children: [
                if (canSelectForBulk)
                  SizedBox(
                    width: 34,
                    child: Checkbox(
                      value: selected,
                      onChanged: isSelf || _busy
                          ? null
                          : (value) => _toggleUserSelection(
                              origin,
                              userId,
                              value == true,
                            ),
                    ),
                  ),
                SizedBox(
                  width: 220,
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: admin
                            ? Colors.deepOrange.withValues(alpha: 0.16)
                            : cs.primary.withValues(alpha: 0.10),
                        foregroundColor: admin ? Colors.deepOrange : cs.primary,
                        child: Text(
                          username.isEmpty ? '?' : username.substring(0, 1),
                          style: appSecondaryControlLabelStyle(context),
                        ),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              username,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: mainText,
                            ),
                            Text(
                              displayName.isEmpty ? userId : displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: subtleText,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    email.isEmpty
                        ? _userText('未绑定邮箱', 'No email')
                        : '$email${emailVerified ? _userText(' · 已验证', ' · Verified') : _userText(' · 未验证', ' · Unverified')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: subtleText,
                  ),
                ),
                SizedBox(
                  width: 178,
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: statusBadges,
                  ),
                ),
                SizedBox(
                  width: 138,
                  child: Text(
                    '$groupName\n$roleName',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: subtleText,
                  ),
                ),
                SizedBox(
                  width: 118,
                  child: Text(
                    '${rawCoinBalance == null ? '-' : coinBalance} / ${rawLifetimeCoins == null ? '-' : lifetimeCoins}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: mainText,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: Text(
                    _userText(
                      '最近登录: $lastLoginAt\n最近活跃: $lastActiveAt',
                      'Last sign in: $lastLoginAt\nLast active: $lastActiveAt',
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: subtleText,
                  ),
                ),
                actionMenu,
              ],
            ),
          );
        }
        final roleBadgeColor = admin ? Colors.deepOrange : Colors.indigo;
        final emailText = email.isEmpty
            ? _userText('未绑定邮箱', 'No email')
            : '$email${emailVerified ? _userText(' · 已验证', ' · Verified') : _userText(' · 未验证', ' · Unverified')}';
        final mobileStatusBadges = <Widget>[
          AppStatusBadge(
            label: online
                ? _userText('在线', 'Online')
                : _userText('离线', 'Offline'),
            color: online ? Colors.green : Colors.grey,
            icon: online ? Icons.circle : Icons.radio_button_unchecked,
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          ),
          if (disabled)
            AppStatusBadge(
              label: _userText('已禁用', 'Disabled'),
              color: cs.error,
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            ),
        ];
        final identityBadges = <Widget>[
          AppStatusBadge(
            label: roleName,
            color: roleBadgeColor,
            icon: Icons.badge_outlined,
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          ),
          AppStatusBadge(
            label: groupName,
            color: cs.primary,
            icon: Icons.groups_2_outlined,
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          ),
          if (admin)
            AppStatusBadge(
              label: _userText('管理员', 'Administrator'),
              color: Colors.deepOrange,
            ),
          if (admin && !permissions.contains(_adminAllPermission))
            AppStatusBadge(
              label: _userText('细分权限', 'Limited permissions'),
              color: Colors.indigo,
            ),
        ];
        return AppSurfaceCard(
          key: ValueKey('admin_user_mobile_card_$userId'),
          padding: EdgeInsets.fromLTRB(10, 9, 4, 10),
          borderRadius: BorderRadius.circular(9),
          border: _adminSubtleListBorder(context),
          onTap: () => _showUserDetails(origin, snapshot),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (canSelectForBulk)
                SizedBox(
                  width: 32,
                  child: Checkbox(
                    value: selected,
                    onChanged: isSelf || _busy
                        ? null
                        : (value) => _toggleUserSelection(
                            origin,
                            userId,
                            value == true,
                          ),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: admin
                              ? Colors.deepOrange.withValues(alpha: 0.18)
                              : cs.primary.withValues(alpha: 0.12),
                          foregroundColor: admin
                              ? Colors.deepOrange
                              : cs.primary,
                          child: Text(
                            username.isEmpty ? '?' : username.substring(0, 1),
                          ),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            username,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.onSurface,
                              fontWeight: FontWeight.normal,
                              decoration: disabled
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ),
                        SizedBox(width: 6),
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: 92),
                          child: Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 4,
                            runSpacing: 4,
                            children: mobileStatusBadges,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Wrap(
                      key: ValueKey('admin_user_identity_badges_$userId'),
                      spacing: 6,
                      runSpacing: 6,
                      children: identityBadges,
                    ),
                    SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      children: [
                        _AdminMobileMetaItem(
                          icon: Icons.alternate_email_outlined,
                          text: emailText,
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _AdminMobileMetric(
                            label: _userText('当前时光币', 'Coin balance'),
                            value: rawCoinBalance == null
                                ? '-'
                                : '$coinBalance',
                            icon: Icons.toll_outlined,
                          ),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: _AdminMobileMetric(
                            label: _userText('累计时光币', 'Lifetime coins'),
                            value: rawLifetimeCoins == null
                                ? '-'
                                : '$lifetimeCoins',
                            icon: Icons.savings_outlined,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      children: [
                        _AdminMobileMetaItem(
                          icon: Icons.how_to_reg_outlined,
                          text: _userText(
                            '注册 $registeredAt',
                            'Registered $registeredAt',
                          ),
                        ),
                        _AdminMobileMetaItem(
                          icon: Icons.login_outlined,
                          text: _userText(
                            '最近登录: $lastLoginAt',
                            'Last sign in: $lastLoginAt',
                          ),
                        ),
                        _AdminMobileMetaItem(
                          icon: Icons.schedule_outlined,
                          text: _userText(
                            '最近活跃: $lastActiveAt',
                            'Last active: $lastActiveAt',
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => _showUserDetails(origin, snapshot),
                        icon: Icon(Icons.more_horiz),
                        label: Text(_userText('更多详情', 'More details')),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 40,
                child: Align(alignment: Alignment.topRight, child: actionMenu),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final origin = _capture();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (!_canReadUsers) {
      return EmptyState(
        icon: Icons.lock_outline,
        message: _userText(
          '缺少用户列表权限。需要用户管理或时光币管理权限。',
          'User list access requires users or coins permission.',
        ),
      );
    }
    final users = List<Map<String, dynamic>>.of(_users);
    final loadingFirstPage = _loading && _page == null;
    final selectableIds = _selectableCurrentPageUserIds;
    final selectedIds = _selectedCurrentPageUserIds;
    final allCurrentPageSelected =
        selectableIds.isNotEmpty && selectedIds.length == selectableIds.length;
    final pageCoinBalance = _users.fold<int>(
      0,
      (sum, user) => sum + _adminIntValue(user['coin_balance']),
    );
    final pageLifetimeCoins = _users.fold<int>(
      0,
      (sum, user) => sum + _adminIntValue(user['lifetime_coins']),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final compactAdminFilters = constraints.maxWidth < 720;
        final userFilterChips = [
          _userFilterChip(origin, _userText('全部账号', 'All accounts'), ''),
          _userFilterChip(origin, _userText('可登录', 'Enabled'), 'active'),
          _userFilterChip(origin, _userText('在线', 'Online'), 'online'),
          _userFilterChip(origin, _userText('离线', 'Offline'), 'offline'),
          _userFilterChip(origin, _userText('管理员', 'Administrator'), 'admin'),
          _userFilterChip(origin, _userText('已禁用', 'Disabled'), 'disabled'),
          _userFilterChip(
            origin,
            _userText('普通用户', 'Standard users'),
            'normal',
          ),
          _userFilterChip(
            origin,
            _userText('有反馈', 'Has feedback'),
            'has_feedback',
          ),
          _userFilterChip(
            origin,
            _userText('邮箱未验证', 'Unverified email'),
            'unverified_email',
          ),
          _userFilterChip(
            origin,
            _userText('邮箱已验证', 'Verified email'),
            'verified_email',
          ),
          _userFilterChip(origin, _userText('未绑定邮箱', 'No email'), 'no_email'),
        ];
        final sortItems = [
          DropdownMenuItem(
            value: 'created_desc',
            child: Text(_userText('最新注册优先', 'Newest accounts')),
          ),
          DropdownMenuItem(
            value: 'last_active_desc',
            child: Text(_userText('最近活跃优先', 'Recently active')),
          ),
          DropdownMenuItem(
            value: 'last_login_desc',
            child: Text(_userText('最近登录优先', 'Recent sign in')),
          ),
          DropdownMenuItem(
            value: 'feedback_desc',
            child: Text(_userText('反馈较多优先', 'Most feedback')),
          ),
          DropdownMenuItem(
            value: 'username_asc',
            child: Text(_userText('用户名 A-Z', 'Username A–Z')),
          ),
          DropdownMenuItem(
            value: 'email_asc',
            child: Text(_userText('邮箱 A-Z', 'Email A–Z')),
          ),
        ];
        return Column(
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: constraints.maxHeight * 0.55,
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    12,
                    compactAdminFilters ? 8 : 12,
                    12,
                    6,
                  ),
                  child: Column(
                    children: [
                      LayoutBuilder(
                        builder: (context, toolbarConstraints) {
                          Widget searchField() => TextField(
                            controller: _searchCtrl,
                            enabled: !_busy,
                            decoration: InputDecoration(
                              hintText: _userText(
                                '搜索用户名、邮箱、昵称或用户 ID',
                                'Search username, email, name or user ID',
                              ),
                              prefixIcon: Icon(Icons.search),
                              suffixIcon: _query.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: _userText(
                                        '清空搜索',
                                        'Clear search',
                                      ),
                                      icon: Icon(Icons.close),
                                      onPressed: () {
                                        if (!_current(origin) || _busy) return;
                                        _searchCtrl.clear();
                                        _load(
                                          origin: origin,
                                          query: '',
                                          offset: 0,
                                        );
                                      },
                                    ),
                              isDense: true,
                            ),
                            textInputAction: TextInputAction.search,
                            onSubmitted: (_) => _applySearch(origin),
                          );

                          List<Widget> toolbarButtons() => [
                            IconButton(
                              tooltip: _userText('搜索用户', 'Search users'),
                              onPressed: _busy
                                  ? null
                                  : () => _applySearch(origin),
                              icon: Icon(Icons.manage_search),
                            ),
                            if (_canManageUsers)
                              IconButton(
                                key: ValueKey('admin_create_user_button'),
                                tooltip: _userText('新增用户', 'Create user'),
                                onPressed: _busy
                                    ? null
                                    : () => _createUser(origin),
                                icon: Icon(Icons.person_add_alt_1_outlined),
                              ),
                            if (_canManageUsers)
                              IconButton(
                                tooltip: _userText(
                                  '导出用户筛选结果',
                                  'Export filtered users',
                                ),
                                onPressed: _busy
                                    ? null
                                    : () => _exportUsersCsv(origin),
                                icon: Icon(Icons.download_outlined),
                              ),
                            IconButton(
                              tooltip: _userText('刷新用户列表', 'Refresh users'),
                              onPressed: _busy
                                  ? null
                                  : () =>
                                        _load(origin: origin, offset: _offset),
                              icon: _loading
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Icon(Icons.refresh),
                            ),
                          ];

                          final buttons = toolbarButtons();
                          final actionWrap = Wrap(
                            key: ValueKey('admin_users_toolbar_actions'),
                            spacing: 2,
                            runSpacing: 2,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: buttons,
                          );
                          if (compactAdminFilters ||
                              toolbarConstraints.maxWidth < 380) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                searchField(),
                                SizedBox(height: 6),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: actionWrap,
                                ),
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(child: searchField()),
                              SizedBox(width: 4),
                              actionWrap,
                            ],
                          );
                        },
                      ),
                      SizedBox(height: 8),
                      compactAdminFilters
                          ? _AdminCompactChipStrip(
                              padding: EdgeInsets.zero,
                              children: userFilterChips,
                            )
                          : _AdminChipWrap(
                              padding: EdgeInsets.zero,
                              children: userFilterChips,
                            ),
                      SizedBox(height: compactAdminFilters ? 4 : 8),
                      if (compactAdminFilters)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: _AdminPaginationLabeledControl(
                            label: _userText('排序', 'Sort'),
                            child: AppCompactDropdown<String>(
                              width: 142,
                              value: _sort,
                              items: sortItems,
                              onChanged: (value) =>
                                  _applySort(origin, value ?? 'created_desc'),
                            ),
                          ),
                        )
                      else
                        AppDropdownField<String>(
                          initialValue: _sort,
                          labelText: _userText('排序', 'Sort'),
                          items: sortItems,
                          onChanged: (value) =>
                              _applySort(origin, value ?? 'created_desc'),
                        ),
                      if (!loadingFirstPage &&
                          _error == null &&
                          _users.isNotEmpty) ...[
                        SizedBox(height: compactAdminFilters ? 6 : 8),
                        AppSurfaceCard(
                          padding: EdgeInsets.fromLTRB(
                            compactAdminFilters ? 8 : 10,
                            compactAdminFilters ? 5 : 8,
                            compactAdminFilters ? 8 : 10,
                            compactAdminFilters ? 5 : 8,
                          ),
                          color: cs.secondaryContainer.withValues(alpha: 0.22),
                          border: Border.all(
                            color: cs.secondary.withValues(alpha: 0.14),
                            width: 0.45,
                          ),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final summaryText = !_canManageUsers
                                  ? _userText(
                                      '本页 ${_users.length} 个 · 时光币 $pageCoinBalance / 累计 $pageLifetimeCoins',
                                      '${_users.length} on this page · Coins $pageCoinBalance / Lifetime $pageLifetimeCoins',
                                    )
                                  : (selectedIds.isEmpty
                                        ? _userText(
                                            '本页 ${_users.length} 个 · 时光币 $pageCoinBalance / 累计 $pageLifetimeCoins',
                                            '${_users.length} on this page · Coins $pageCoinBalance / Lifetime $pageLifetimeCoins',
                                          )
                                        : _userText(
                                            '已选 ${selectedIds.length} 个 · 当前页批量操作',
                                            '${selectedIds.length} selected · Actions apply to this page',
                                          ));
                              final summary = Text(
                                summaryText,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurface.withValues(alpha: 0.68),
                                ),
                              );
                              final actions = Wrap(
                                spacing: 8,
                                runSpacing: compactAdminFilters ? 2 : 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: _canManageUsers
                                    ? [
                                        FilterChip(
                                          label: Text(
                                            allCurrentPageSelected
                                                ? _userText(
                                                    '取消全选本页',
                                                    'Deselect page',
                                                  )
                                                : _userText(
                                                    '全选本页',
                                                    'Select page',
                                                  ),
                                          ),
                                          selected: allCurrentPageSelected,
                                          onSelected:
                                              selectableIds.isEmpty || _busy
                                              ? null
                                              : (_) =>
                                                    _toggleCurrentPageSelection(
                                                      origin,
                                                      !allCurrentPageSelected,
                                                    ),
                                        ),
                                        TextButton.icon(
                                          onPressed:
                                              selectedIds.isEmpty || _busy
                                              ? null
                                              : () => _bulkSetDisabled(
                                                  origin,
                                                  true,
                                                ),
                                          icon: Icon(Icons.block_outlined),
                                          label: Text(
                                            _userText(
                                              '批量禁用',
                                              'Disable selected',
                                            ),
                                          ),
                                        ),
                                        TextButton.icon(
                                          onPressed:
                                              selectedIds.isEmpty || _busy
                                              ? null
                                              : () => _bulkSetDisabled(
                                                  origin,
                                                  false,
                                                ),
                                          icon: Icon(Icons.lock_open_outlined),
                                          label: Text(
                                            _userText(
                                              '批量恢复',
                                              'Restore selected',
                                            ),
                                          ),
                                        ),
                                      ]
                                    : [],
                              );
                              if (compactAdminFilters ||
                                  constraints.maxWidth < 560) {
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    summary,
                                    SizedBox(height: 6),
                                    actions,
                                  ],
                                );
                              }
                              return Row(
                                children: [
                                  Expanded(child: summary),
                                  actions,
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                      _AdminInlineLoadingIndicator(
                        visible: _loading && _page != null,
                        label: _userText('正在更新当前页', 'Updating this page'),
                      ),
                      if (_refreshError != null) ...[
                        SizedBox(height: 8),
                        AppInfoBanner(
                          icon: Icons.refresh,
                          title: _userText(
                            '刷新失败，仍显示上次结果',
                            'Refresh failed. Showing previous results.',
                          ),
                          message: _adminErrorMessage(
                            _refreshError!,
                            _userText('用户列表', 'Users'),
                          ),
                          color: cs.error,
                          margin: EdgeInsets.zero,
                        ),
                      ],
                      if (_auxiliaryErrors.isNotEmpty) ...[
                        SizedBox(height: 8),
                        AppInfoBanner(
                          icon: Icons.lock_outline,
                          title: _userText(
                            '用户组或角色加载失败',
                            'Could not load groups or roles',
                          ),
                          message: _auxiliaryErrors
                              .map(
                                (entry) => _adminErrorMessage(
                                  entry.$1,
                                  entry.$2 == 'groups'
                                      ? _userText('用户组', 'Groups')
                                      : _userText('角色', 'Roles'),
                                ),
                              )
                              .join('\n'),
                          color: cs.error,
                          margin: EdgeInsets.zero,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            if (loadingFirstPage)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text(_userText('正在加载用户列表…', 'Loading users…')),
                    ],
                  ),
                ),
              )
            else if (_error != null)
              Expanded(
                child: _AdminErrorState(
                  message: _adminErrorMessage(
                    _error!,
                    _userText('用户列表', 'Users'),
                  ),
                  onRetry: _failedLoad ?? () async {},
                ),
              )
            else if (_users.isEmpty)
              Expanded(
                child: EmptyState(
                  icon: Icons.people_outline,
                  message: _query.isEmpty && _status.isEmpty
                      ? _userText('暂无用户记录', 'No users yet')
                      : _userText(
                          '没有匹配的用户。请调整搜索关键词或账号状态筛选。',
                          'No matching users. Adjust your search or account filters.',
                        ),
                ),
              )
            else
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () => _load(origin: origin, offset: _offset),
                  child: ListView.separated(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    itemCount: users.length,
                    separatorBuilder: (context, _) => SizedBox(height: 8),
                    itemBuilder: (_, i) => Builder(
                      builder: (itemContext) =>
                          _buildUserListItem(itemContext, users[i]),
                    ),
                  ),
                ),
              ),
            _AdminPaginationBar(
              page: _page,
              loading: _busy,
              pageSize: _pageSize,
              onPageSizeChanged: (value) =>
                  _load(origin: origin, pageSize: value, offset: 0),
              onPrevious: () => _load(
                origin: origin,
                offset: _previousAdminOffset(_offset, _pageSize),
              ),
              onNext: () => _load(origin: origin, offset: _offset + _pageSize),
              onJumpToPage: (page) => _jumpToPage(origin, page),
            ),
          ],
        );
      },
    );
  }

  Widget _userFilterChip(_UserAction origin, String label, String value) {
    final selected = _status == value;
    return Padding(
      padding: EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: _busy ? null : (_) => _applyStatus(origin, value),
      ),
    );
  }
}

// ====================================================================
// 公告
// ====================================================================

/// The view generation is separate from account authority, and changes at the
/// TabController event itself so a same-frame leave/return revokes old controls.
class _AnnouncementAction {
  _AnnouncementAction(this.authority, this.view) : _viewRevision = view.value;

  final AdminActionOrigin authority;
  final ValueListenable<int> view;
  final int _viewRevision;

  ApiClient get client => authority.client;

  bool isCurrent({bool checkRoute = true}) =>
      view.value == _viewRevision &&
      authority.isCurrent(checkRoute: checkRoute);
}

class _AnnouncementsTab extends StatefulWidget {
  final AdminApi api;
  final bool isActive;
  final ValueListenable<int> activationRevision;

  const _AnnouncementsTab({
    super.key,
    required this.api,
    required this.isActive,
    required this.activationRevision,
  });

  @override
  State<_AnnouncementsTab> createState() => _AnnouncementsTabState();
}

class _AnnouncementsTabState extends State<_AnnouncementsTab> {
  final _actionHost = AdminActionHost();
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _items = [];
  AdminPage? _page;
  bool _loading = true;
  bool _mutationPending = false;
  Object? _error;
  String _query = '';
  String _status = '';
  String _level = '';
  String _sort = 'created_desc';
  int _pageSize = _adminPageSize;
  int _offset = 0;
  int _loadSerial = 0;
  int? _authorityRevision;
  int? _viewRevision;
  Future<void> Function()? _failedLoad;
  Route<dynamic>? _sortMenuRoute;
  int? _sortMenuAuthorityRevision;
  int? _sortMenuViewRevision;

  _AnnouncementAction _capture() => _AnnouncementAction(
    _actionHost.capture(
      client: widget.api.client,
      anyOfPermissions: const {'announcements'},
    ),
    widget.activationRevision,
  );

  bool _isCurrent(_AnnouncementAction origin, {bool checkRoute = true}) =>
      mounted && widget.isActive && origin.isCurrent(checkRoute: checkRoute);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _actionHost.bind(context);
    _viewRevision ??= widget.activationRevision.value;
    final revision = _actionHost.revision;
    if (_authorityRevision == revision) return;
    _authorityRevision = revision;
    _loadSerial++;
    _items = [];
    _page = null;
    _failedLoad = null;
    _error = null;
    _query = '';
    _status = '';
    _level = '';
    _sort = 'created_desc';
    _offset = 0;
    _searchCtrl.clear();
    final origin = _capture();
    if (_isCurrent(origin)) {
      _load(origin: origin);
    } else {
      _loading = false;
    }
  }

  @override
  void didUpdateWidget(covariant _AnnouncementsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    final viewRevision = widget.activationRevision.value;
    if (oldWidget.isActive == widget.isActive &&
        _viewRevision == viewRevision) {
      return;
    }
    _viewRevision = viewRevision;
    final serial = ++_loadSerial;
    _failedLoad = null;
    _loading = false;
    if (widget.isActive) {
      final origin = _capture();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // A dependency change may have already cleared and reloaded this view.
        if (serial == _loadSerial && _isCurrent(origin)) {
          _load(origin: origin);
        }
      });
    }
  }

  @override
  void dispose() {
    _loadSerial++;
    _actionHost.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<bool> _load({
    required _AnnouncementAction origin,
    _AnnouncementAction? mutationOrigin,
    int? offset,
    String? query,
    String? status,
    String? level,
    String? sort,
    int? pageSize,
  }) async {
    bool current() =>
        _isCurrent(origin) &&
        (mutationOrigin == null || _isCurrent(mutationOrigin));
    if (!current()) return false;
    final serial = ++_loadSerial;
    final nextOffset = offset ?? _offset;
    final nextQuery = query ?? _query;
    final nextStatus = status ?? _status;
    final nextLevel = level ?? _level;
    final nextSort = sort ?? _sort;
    final nextPageSize = pageSize ?? _pageSize;
    setState(() {
      _offset = nextOffset;
      _query = nextQuery;
      _status = nextStatus;
      _level = nextLevel;
      _sort = nextSort;
      _pageSize = nextPageSize;
      _loading = true;
      _error = null;
    });
    try {
      final page = await AdminApi(origin.client).listAnnouncementsPage(
        query: nextQuery.isEmpty ? null : nextQuery,
        status: nextStatus.isEmpty ? null : nextStatus,
        level: nextLevel.isEmpty ? null : nextLevel,
        sort: nextSort,
        limit: nextPageSize,
        offset: nextOffset,
        isCurrent: current,
      );
      if (!current() || serial != _loadSerial) return false;
      _page = page;
      _items = page.items;
      _failedLoad = null;
      return true;
    } catch (error) {
      if (!current() || serial != _loadSerial) return false;
      _error = error;
      _failedLoad = () async {
        await _load(
          origin: origin,
          mutationOrigin: mutationOrigin,
          offset: nextOffset,
          query: nextQuery,
          status: nextStatus,
          level: nextLevel,
          sort: nextSort,
          pageSize: nextPageSize,
        );
      };
      return false;
    } finally {
      if (mounted && serial == _loadSerial) setState(() => _loading = false);
    }
  }

  void _showSnack(_AnnouncementAction origin, String Function(AppLocale) copy) {
    if (!_isCurrent(origin)) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: _AdminFeedbackText(copy)));
  }

  bool _closeDialog(
    BuildContext ctx,
    ModalRoute<dynamic> route,
    _AnnouncementAction origin,
    bool confirmed,
  ) {
    if (!ctx.mounted ||
        !route.isActive ||
        !route.isCurrent ||
        (confirmed && !_isCurrent(origin, checkRoute: false))) {
      return false;
    }
    Navigator.of(ctx).pop(confirmed);
    return true;
  }

  Future<void> _refreshAfterMutation(
    _AnnouncementAction origin,
    String Function(AppLocale) success, {
    int? offset,
  }) async {
    if (!_isCurrent(origin)) return;
    final reloaded = await _load(
      origin: _capture(),
      mutationOrigin: origin,
      offset: offset ?? _offset,
    );
    _showSnack(
      origin,
      (locale) => reloaded
          ? success(locale)
          : AdminAnnouncementUiCopy.refreshFailed(success(locale), locale),
    );
  }

  Future<void> _openEdit(
    _AnnouncementAction origin, {
    Map<String, dynamic>? item,
  }) async {
    if (_mutationPending || !_isCurrent(origin)) return;
    setState(() => _mutationPending = true);
    final titleCtrl = TextEditingController(
      text: (item?['title'] ?? '').toString(),
    );
    final bodyCtrl = TextEditingController(
      text: (item?['body'] ?? '').toString(),
    );
    var level = (item?['level'] ?? 'info').toString();
    var published =
        item == null || item['published'] == 1 || item['published'] == true;
    var showErrors = false;
    DialogRoute<bool>? dialogRoute;
    Route<dynamic>? levelMenuRoute;
    var pushed = false;
    bool canEdit() =>
        _isCurrent(origin, checkRoute: false) &&
        dialogRoute?.isActive == true &&
        dialogRoute?.isCurrent == true;
    bool canSelectLevel() =>
        _isCurrent(origin, checkRoute: false) &&
        dialogRoute?.isActive == true &&
        ((levelMenuRoute?.isActive == true &&
                levelMenuRoute?.isCurrent == true) ||
            dialogRoute?.isCurrent == true);
    try {
      dialogRoute = DialogRoute<bool>(
        context: context,
        builder: (ctx) => ValueListenableBuilder<AppLocale>(
          valueListenable: I18n.localeListenable,
          builder: (ctx, locale, _) => StatefulBuilder(
            builder: (ctx, setSt) => AppDialog(
              title: Text(
                item == null
                    ? AdminAnnouncementUiCopy.newTitleFor(locale)
                    : AdminAnnouncementUiCopy.editTitleFor(locale),
              ),
              icon: _dialogIcon(ctx, Icons.campaign_outlined),
              content: _adminDialogForm(
                maxWidth: 430,
                children: [
                  TextField(
                    controller: titleCtrl,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: AdminAnnouncementUiCopy.titleLabelFor(locale),
                      errorText: showErrors && titleCtrl.text.trim().isEmpty
                          ? AdminAnnouncementUiCopy.titleRequiredFor(locale)
                          : null,
                      errorMaxLines: 3,
                    ),
                    onChanged: (_) {
                      if (showErrors && canEdit()) {
                        setSt(() {});
                      }
                    },
                  ),
                  TextField(
                    controller: bodyCtrl,
                    minLines: 3,
                    maxLines: 6,
                    decoration: InputDecoration(
                      labelText: AdminAnnouncementUiCopy.bodyLabelFor(locale),
                      errorText: showErrors && bodyCtrl.text.trim().isEmpty
                          ? AdminAnnouncementUiCopy.bodyRequiredFor(locale)
                          : null,
                      errorMaxLines: 3,
                    ),
                    onChanged: (_) {
                      if (showErrors && canEdit()) {
                        setSt(() {});
                      }
                    },
                  ),
                  AppDropdownField<String>(
                    initialValue: level,
                    isInteractionAllowed: canEdit,
                    isSelectionAllowed: canSelectLevel,
                    onMenuRouteCreated: (route) {
                      if (_isCurrent(origin, checkRoute: false) &&
                          dialogRoute?.isActive == true) {
                        levelMenuRoute = route;
                      }
                    },
                    labelText: AdminAnnouncementUiCopy.levelLabelFor(locale),
                    items: [
                      for (final value in {
                        'info',
                        'warning',
                        'critical',
                        level,
                      })
                        DropdownMenuItem(
                          value: value,
                          child: _AdminFeedbackText(
                            (locale) => AdminAnnouncementUiCopy.levelLabel(
                              value,
                              locale,
                            ),
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      if (canEdit() && value != null) {
                        setSt(() => level = value);
                      }
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: published,
                    title: Text(AdminAnnouncementUiCopy.publishNowFor(locale)),
                    subtitle: Text(
                      AdminAnnouncementUiCopy.publishHelperFor(locale),
                    ),
                    onChanged: (value) {
                      if (canEdit()) setSt(() => published = value);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () =>
                      _closeDialog(ctx, dialogRoute!, origin, false),
                  child: Text(AdminUiCopy.cancelFor(locale)),
                ),
                FilledButton(
                  onPressed: () {
                    if (!canEdit()) return;
                    if (titleCtrl.text.trim().isEmpty ||
                        bodyCtrl.text.trim().isEmpty) {
                      setSt(() => showErrors = true);
                      return;
                    }
                    _closeDialog(ctx, dialogRoute!, origin, true);
                  },
                  child: Text(AdminUiCopy.saveFor(locale)),
                ),
              ],
            ),
          ),
        ),
      );
      final result = Navigator.of(context).push(dialogRoute);
      pushed = true;
      final saved = await result;
      await dialogRoute.completed;
      if (saved != true || !_isCurrent(origin)) return;
      bool current() => _isCurrent(origin);
      final api = AdminApi(origin.client);
      if (item == null) {
        await api.createAnnouncement(
          title: titleCtrl.text.trim(),
          body: bodyCtrl.text.trim(),
          level: level,
          published: published,
          isCurrent: current,
        );
      } else {
        await api.updateAnnouncement(
          (item['id'] as num).toInt(),
          title: titleCtrl.text.trim(),
          body: bodyCtrl.text.trim(),
          level: level,
          published: published,
          isCurrent: current,
        );
      }
      await _refreshAfterMutation(origin, AdminAnnouncementUiCopy.savedFor);
    } catch (error) {
      _showSnack(
        origin,
        (locale) => _adminActionErrorMessage(
          error,
          AdminAnnouncementUiCopy.saveActionFor(locale),
          locale,
        ),
      );
    } finally {
      if (pushed) await dialogRoute!.completed;
      titleCtrl.dispose();
      bodyCtrl.dispose();
      if (mounted) setState(() => _mutationPending = false);
    }
  }

  Future<void> _toggle(
    _AnnouncementAction origin,
    Map<String, dynamic> item,
  ) async {
    if (_mutationPending || !_isCurrent(origin)) return;
    setState(() => _mutationPending = true);
    final published = item['published'] == 1 || item['published'] == true;
    try {
      await AdminApi(origin.client).updateAnnouncement(
        (item['id'] as num).toInt(),
        published: !published,
        isCurrent: () => _isCurrent(origin),
      );
      await _refreshAfterMutation(
        origin,
        published
            ? AdminAnnouncementUiCopy.unpublishedSuccessFor
            : AdminAnnouncementUiCopy.publishedSuccessFor,
      );
    } catch (error) {
      _showSnack(
        origin,
        (locale) => _adminActionErrorMessage(
          error,
          published
              ? AdminAnnouncementUiCopy.unpublishActionFor(locale)
              : AdminAnnouncementUiCopy.publishActionFor(locale),
          locale,
        ),
      );
    } finally {
      if (mounted) setState(() => _mutationPending = false);
    }
  }

  Future<void> _delete(
    _AnnouncementAction origin,
    Map<String, dynamic> item,
  ) async {
    if (_mutationPending || !_isCurrent(origin)) return;
    setState(() => _mutationPending = true);
    DialogRoute<bool>? dialogRoute;
    var pushed = false;
    try {
      final title = (item['title'] ?? '').toString();
      dialogRoute = DialogRoute<bool>(
        context: context,
        builder: (ctx) => ValueListenableBuilder<AppLocale>(
          valueListenable: I18n.localeListenable,
          builder: (ctx, locale, _) => AppDialog(
            title: Text(AdminAnnouncementUiCopy.deleteTitleFor(locale)),
            icon: _dialogIcon(ctx, Icons.delete_outline),
            content: Text(AdminAnnouncementUiCopy.deleteBody(title, locale)),
            actions: [
              TextButton(
                onPressed: () => _closeDialog(ctx, dialogRoute!, origin, false),
                child: Text(AdminUiCopy.cancelFor(locale)),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                  foregroundColor: Theme.of(ctx).colorScheme.onError,
                ),
                onPressed: () => _closeDialog(ctx, dialogRoute!, origin, true),
                child: Text(AdminUiCopy.deleteFor(locale)),
              ),
            ],
          ),
        ),
      );
      final result = Navigator.of(context).push(dialogRoute);
      pushed = true;
      final confirmed = await result;
      await dialogRoute.completed;
      if (confirmed != true || !_isCurrent(origin)) return;
      await AdminApi(origin.client).deleteAnnouncement(
        (item['id'] as num).toInt(),
        isCurrent: () => _isCurrent(origin),
      );
      await _refreshAfterMutation(
        origin,
        AdminAnnouncementUiCopy.deletedFor,
        offset: _offsetAfterAdminDelete(
          offset: _offset,
          itemCount: _items.length,
          pageSize: _pageSize,
        ),
      );
    } catch (error) {
      _showSnack(
        origin,
        (locale) => _adminActionErrorMessage(
          error,
          AdminAnnouncementUiCopy.deleteActionFor(locale),
          locale,
        ),
      );
    } finally {
      if (pushed) await dialogRoute!.completed;
      if (mounted) setState(() => _mutationPending = false);
    }
  }

  Widget? _dialogIcon(BuildContext context, IconData icon) {
    final media = MediaQuery.of(context);
    // Give large-text titles the full row on narrow screens.
    if (media.size.width < 360 && media.textScaler.scale(16) >= 30) {
      return null;
    }
    return Icon(icon);
  }

  @override
  Widget build(BuildContext context) {
    final origin = _capture();
    final authorityRevision = _actionHost.revision;
    final viewRevision = widget.activationRevision.value;
    bool canSelectSort() =>
        _isCurrent(origin, checkRoute: false) &&
        ((_sortMenuRoute?.isActive == true &&
                _sortMenuRoute?.isCurrent == true &&
                _sortMenuAuthorityRevision == authorityRevision &&
                _sortMenuViewRevision == viewRevision &&
                _actionHost.revision == authorityRevision &&
                widget.activationRevision.value == viewRevision) ||
            _isCurrent(origin));
    final theme = Theme.of(context);
    final failedLoad = _failedLoad;
    Future<void> retry() async {
      if (!_isCurrent(origin)) return;
      if (failedLoad != null) {
        await failedLoad();
      } else {
        await _load(origin: origin);
      }
    }

    final error = _error == null
        ? null
        : _adminErrorMessage(_error!, AdminAnnouncementUiCopy.listTargetFor());
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              await _load(origin: origin);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                Text(
                  AdminAnnouncementUiCopy.listTitleFor(),
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  _adminPageSummary(_page),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _mutationPending
                          ? null
                          : () => _openEdit(origin),
                      icon: const Icon(Icons.add),
                      label: Text(AdminAnnouncementUiCopy.newTitleFor()),
                    ),
                    TextButton.icon(
                      onPressed: _loading ? null : () => _load(origin: origin),
                      icon: const Icon(Icons.refresh),
                      label: Text(AdminUiCopy.refreshFor()),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: AdminAnnouncementUiCopy.searchHintFor(),
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: AdminAnnouncementUiCopy.clearSearchFor(),
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              if (!_isCurrent(origin)) return;
                              _searchCtrl.clear();
                              _load(origin: origin, query: '', offset: 0);
                            },
                          ),
                    isDense: true,
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) {
                    if (_isCurrent(origin)) {
                      _load(
                        origin: origin,
                        query: _searchCtrl.text.trim(),
                        offset: 0,
                      );
                    }
                  },
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final value in ['', 'published', 'draft'])
                      ChoiceChip(
                        label: Text(switch (value) {
                          'published' => AdminAnnouncementUiCopy.publishedFor(),
                          'draft' => AdminAnnouncementUiCopy.draftFor(),
                          _ => AdminAnnouncementUiCopy.allStatusesFor(),
                        }),
                        selected: _status == value,
                        onSelected: (_) =>
                            _load(origin: origin, status: value, offset: 0),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final value in ['', 'info', 'warning', 'critical'])
                      ChoiceChip(
                        label: Text(
                          value.isEmpty
                              ? AdminAnnouncementUiCopy.allLevelsFor()
                              : AdminAnnouncementUiCopy.levelLabel(value),
                        ),
                        selected: _level == value,
                        onSelected: (_) =>
                            _load(origin: origin, level: value, offset: 0),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                AppDropdownField<String>(
                  key: ValueKey((
                    'admin-announcements-sort',
                    _authorityRevision,
                  )),
                  initialValue: _sort,
                  isInteractionAllowed: () => _isCurrent(origin),
                  isSelectionAllowed: canSelectSort,
                  onMenuRouteCreated: (route) {
                    if (!_isCurrent(origin, checkRoute: false)) return;
                    _sortMenuRoute = route;
                    _sortMenuAuthorityRevision = authorityRevision;
                    _sortMenuViewRevision = viewRevision;
                  },
                  labelText: AdminAnnouncementUiCopy.sortTitleFor(),
                  items: [
                    for (final value in [
                      'created_desc',
                      'updated_desc',
                      'level_desc',
                      'title_asc',
                    ])
                      DropdownMenuItem(
                        value: value,
                        child: _AdminFeedbackText(
                          (locale) =>
                              _adminAnnouncementSortLabel(value, locale),
                        ),
                      ),
                  ],
                  onChanged: (value) => _load(
                    origin: origin,
                    sort: value ?? 'created_desc',
                    offset: 0,
                  ),
                ),
                const SizedBox(height: 12),
                _AdminInlineLoadingIndicator(
                  visible: _loading && _page != null,
                  label: AdminAnnouncementUiCopy.updatingFor(),
                ),
                if (_loading && _page == null)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 12),
                        Text(AdminAnnouncementUiCopy.loadingFor()),
                      ],
                    ),
                  )
                else if (error != null)
                  _AdminErrorState(message: error, onRetry: retry)
                else if (_items.isEmpty)
                  EmptyState(
                    icon: Icons.campaign_outlined,
                    message: _query.isEmpty && _status.isEmpty && _level.isEmpty
                        ? AdminAnnouncementUiCopy.emptyFor()
                        : AdminAnnouncementUiCopy.noMatchesFor(),
                  )
                else
                  for (final item in _items)
                    _announcementCard(context, origin, item),
              ],
            ),
          ),
        ),
        _AdminPaginationBar(
          barKey: const ValueKey('admin_announcements_pagination_bar'),
          page: _page,
          loading: _loading,
          pageSize: _pageSize,
          onPageSizeChanged: (value) =>
              _load(origin: origin, pageSize: value, offset: 0),
          onPrevious: () => _load(
            origin: origin,
            offset: _previousAdminOffset(_offset, _pageSize),
          ),
          onNext: () => _load(origin: origin, offset: _offset + _pageSize),
          onJumpToPage: (page) =>
              _load(origin: origin, offset: (page - 1) * _pageSize),
        ),
      ],
    );
  }

  Widget _announcementCard(
    BuildContext context,
    _AnnouncementAction origin,
    Map<String, dynamic> item,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final published = item['published'] == 1 || item['published'] == true;
    final level = (item['level'] ?? 'info').toString();
    final levelColor = switch (level) {
      'critical' => cs.error,
      'warning' => Colors.orange,
      _ => cs.primary,
    };
    String timestamp(Object? value) {
      final text = (value ?? '').toString();
      final date = DateTime.tryParse(text);
      return date == null ? text : I18nDateFormat.shortDateTime(date);
    }

    return AppSurfaceCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      border: _adminSubtleListBorder(context),
      elevation: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  (item['title'] ?? '').toString(),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.normal,
                    color: cs.onSurface,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                enabled: !_mutationPending,
                tooltip: AdminAnnouncementUiCopy.menuTooltipFor(),
                onSelected: (action) async {
                  if (!_isCurrent(origin)) return;
                  switch (action) {
                    case 'edit':
                      await _openEdit(origin, item: item);
                      return;
                    case 'toggle':
                      await _toggle(origin, item);
                      return;
                    case 'delete':
                      await _delete(origin, item);
                      return;
                  }
                },
                itemBuilder: (_) => [
                  for (final action in ['edit', 'toggle', 'delete'])
                    PopupMenuItem(
                      value: action,
                      child: ValueListenableBuilder<AppLocale>(
                        valueListenable: I18n.localeListenable,
                        builder: (_, locale, _) => AppSecondaryMenuText(
                          switch (action) {
                            'edit' => AdminAnnouncementUiCopy.editFor(locale),
                            'toggle' =>
                              published
                                  ? AdminAnnouncementUiCopy.unpublishFor(locale)
                                  : AdminAnnouncementUiCopy.publishFor(locale),
                            _ => AdminUiCopy.deleteFor(locale),
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              AppStatusBadge(
                label: AdminAnnouncementUiCopy.levelLabel(level),
                color: levelColor,
              ),
              AppStatusBadge(
                label: published
                    ? AdminAnnouncementUiCopy.publishedFor()
                    : AdminAnnouncementUiCopy.draftFor(),
                color: published ? cs.primary : cs.onSurfaceVariant,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            (item['body'] ?? '').toString(),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            AdminAnnouncementUiCopy.createdAt(timestamp(item['created_at'])),
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          if (item['updated_at'] != null)
            Text(
              AdminAnnouncementUiCopy.updatedAt(timestamp(item['updated_at'])),
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

// ====================================================================
// 反馈
// ====================================================================

class _FeedbackAction {
  _FeedbackAction(this.authority, this.view, this.foreground)
    : _viewRevision = view.value,
      _foregroundRevision = foreground();
  final AdminActionOrigin authority;
  final ValueListenable<int> view;
  final int _viewRevision;
  final int Function() foreground;
  final int _foregroundRevision;
  ApiClient get client => authority.client;
  bool isCurrent({bool checkRoute = true}) =>
      view.value == _viewRevision &&
      foreground() == _foregroundRevision &&
      authority.isCurrent(checkRoute: checkRoute);
}

class _FeedbackOperation {
  _FeedbackOperation(this.origin);
  final _FeedbackAction origin;
  DialogRoute<dynamic>? dialog;
  DialogRoute<dynamic>? selector;
}

class _FeedbackModalGuard extends StatefulWidget {
  const _FeedbackModalGuard({required this.onCovered, required this.child});
  final VoidCallback onCovered;
  final Widget child;
  @override
  State<_FeedbackModalGuard> createState() => _FeedbackModalGuardState();
}

class _FeedbackModalGuardState extends State<_FeedbackModalGuard> {
  bool? _wasCurrent;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    final current = route?.isCurrent ?? true;
    if (_wasCurrent == true && !current && route?.isActive == true) {
      widget.onCovered();
    }
    _wasCurrent = current;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _FeedbackTab extends StatefulWidget {
  final AdminApi api;
  final AdminFeedbackExportEffects exportEffects;
  final bool Function() isActiveNow;
  final ValueListenable<int> activationRevision;

  const _FeedbackTab({
    super.key,
    required this.api,
    required this.exportEffects,
    required this.isActiveNow,
    required this.activationRevision,
  });

  @override
  State<_FeedbackTab> createState() => _FeedbackTabState();
}

class _FeedbackTabState extends State<_FeedbackTab> {
  final _actionHost = AdminActionHost();
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<Map<String, dynamic>> _items = [];
  AdminPage? _page;
  Object? _error;
  Future<void> Function()? _failedLoad;
  bool _loading = false;
  bool _readNeedsReload = false;
  bool _loadScheduled = false;
  bool _rebuildScheduled = false;
  bool? _wasForeground;
  int _foregroundRevision = 0;
  _FeedbackOperation? _operation;
  AppAccessRouteGate? _routeEvents;
  ModalRoute<dynamic>? _pageRoute;
  Route<dynamic>? _lastTopRoute;
  String _filter = '';
  String _categoryFilter = '';
  final _uiRevision = ValueNotifier<int>(0);
  String _query = '';
  String _sort = 'created_desc';
  int _pageSize = _adminPageSize;
  int _offset = 0;
  int _loadSerial = 0;
  int? _authorityRevision;
  int? _viewRevision;

  bool get _readBusy => _loading || _readNeedsReload;
  bool get _isActive => widget.isActiveNow();

  @override
  void initState() {
    super.initState();
    _viewRevision = widget.activationRevision.value;
    widget.activationRevision.addListener(_onViewEvent);
  }

  // A tab can leave and return before TabBarView updates this child. Suspend
  // its read immediately and arrange recovery from a fresh receipt next frame.
  void _onViewEvent() {
    if (!mounted) return;
    final revision = widget.activationRevision.value;
    if (_viewRevision == revision) return;
    _viewRevision = revision;
    _invalidate();
    _scheduleRebuild();
    _deferLoad();
  }

  void _bindRouteEvents() {
    _pageRoute = ModalRoute.of(context);
    final observers = Navigator.of(context).widget.observers;
    AppAccessRouteGate? source;
    for (final observer in observers) {
      if (observer is AppAccessRouteGate) {
        source = observer;
        break;
      }
    }
    if (identical(source, _routeEvents)) return;
    _routeEvents?.routeRevision.removeListener(_onRouteEvent);
    _routeEvents = source;
    _lastTopRoute = source?.currentRoute;
    source?.routeRevision.addListener(_onRouteEvent);
  }

  void _onRouteEvent() {
    if (!mounted) return;
    final top = _routeEvents?.currentRoute;
    if (identical(top, _lastTopRoute)) return;
    _lastTopRoute = top;
    final foreground = identical(top, _pageRoute);
    _wasForeground = foreground;
    if (!foreground) {
      if (_operation != null &&
          (top != null &&
              (identical(top, _operation!.dialog) ||
                  identical(top, _operation!.selector)))) {
        final needsReload = _loading || _readNeedsReload;
        _loadSerial++;
        _loading = false;
        _readNeedsReload = needsReload;
      } else {
        _foregroundRevision++;
        _invalidate();
      }
      _scheduleRebuild();
    } else if (_readNeedsReload) {
      _deferLoad();
    }
  }

  _FeedbackAction _capture() {
    _syncAuthority();
    return _FeedbackAction(
      _actionHost.capture(
        client: widget.api.client,
        anyOfPermissions: const {'feedback'},
      ),
      widget.activationRevision,
      () => _foregroundRevision,
    );
  }

  bool _isCurrent(_FeedbackAction origin, {bool checkRoute = true}) {
    if (!mounted) return false;
    _syncAuthority();
    return _isActive && origin.isCurrent(checkRoute: checkRoute);
  }

  // A client token/base URL can change without a provider notification. Never
  // give the previous server's displayed data a receipt for the new authority.
  void _syncAuthority() {
    final revision = _actionHost.revision;
    if (_authorityRevision == revision) return;
    _authorityRevision = revision;
    _invalidate(clearPrivateData: true);
    _deferLoad();
  }

  void _invalidate({bool clearPrivateData = false}) {
    _loadSerial++;
    _loading = false;
    _readNeedsReload = _isActive;
    _failedLoad = null;
    _operation = null;
    if (!clearPrivateData) return;
    _items = [];
    _page = null;
    _error = null;
    _filter = '';
    _categoryFilter = '';
    _query = '';
    _sort = 'created_desc';
    _pageSize = _adminPageSize;
    _offset = 0;
    _searchCtrl.clear();
    _scheduleRebuild();
  }

  void _scheduleRebuild() {
    if (!mounted || _rebuildScheduled) return;
    _rebuildScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rebuildScheduled = false;
      if (mounted) {
        _uiRevision.value++;
        setState(() {});
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  // Route dependencies schedule this again when a covering route is removed.
  // Do not hold a receipt captured while the Admin page is underneath a route.
  void _deferLoad() {
    if (!mounted || !_isActive || _loadScheduled || _operation != null) {
      return;
    }
    _loadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadScheduled = false;
      if (!mounted ||
          !_isActive ||
          !_readNeedsReload ||
          _loading ||
          _operation != null) {
        return;
      }
      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent) return;
      final origin = _capture();
      if (_isCurrent(origin)) {
        unawaited(_load(origin: origin));
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _actionHost.bind(context);
    _bindRouteEvents();
    _viewRevision ??= widget.activationRevision.value;
    _syncAuthority();
    final foreground = ModalRoute.of(context)?.isCurrent ?? true;
    if (_wasForeground == true && !foreground) {
      if (_operation == null) {
        _foregroundRevision++;
        _invalidate();
      } else {
        // Suspend an in-flight read without revoking our own picker. Opening
        // and canceling a picker on settled data does not issue another GET.
        final needsReload = _loading || _readNeedsReload;
        _loadSerial++;
        _loading = false;
        _readNeedsReload = needsReload;
      }
    }
    _wasForeground = foreground;
    if (_readNeedsReload) _deferLoad();
  }

  @override
  void didUpdateWidget(covariant _FeedbackTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.activationRevision, widget.activationRevision)) {
      oldWidget.activationRevision.removeListener(_onViewEvent);
      widget.activationRevision.addListener(_onViewEvent);
      _viewRevision = null;
    }
    _syncAuthority();
    final revision = widget.activationRevision.value;
    // A revision already handled by the synchronous listener must not start
    // another read when TabBarView eventually updates its cached child.
    if (_viewRevision == revision) return;
    _viewRevision = revision;
    _invalidate();
    if (_isActive) _deferLoad();
  }

  @override
  void dispose() {
    _loadSerial++;
    widget.activationRevision.removeListener(_onViewEvent);
    _operation = null;
    _uiRevision.dispose();
    _actionHost.dispose();
    _routeEvents?.routeRevision.removeListener(_onRouteEvent);
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<bool> _load({
    required _FeedbackAction origin,
    int? offset,
    String? status,
    String? category,
    _FeedbackOperation? operation,
    String? query,
    String? sort,
    int? pageSize,
  }) async {
    bool valid() =>
        _isCurrent(origin) &&
        (operation == null ? _operation == null : _operationCurrent(operation));
    if (!valid()) return false;
    final serial = ++_loadSerial;
    bool current() => serial == _loadSerial && valid();
    final nextOffset = offset ?? _offset;
    final nextStatus = status ?? _filter;
    final nextCategory = category ?? _categoryFilter;
    final nextQuery = query ?? _query;
    final nextSort = sort ?? _sort;
    final nextPageSize = pageSize ?? _pageSize;
    setState(() {
      _offset = nextOffset;
      _filter = nextStatus;
      _categoryFilter = nextCategory;
      _query = nextQuery;
      _sort = nextSort;
      _pageSize = nextPageSize;
      _loading = true;
      _readNeedsReload = false;
      _error = null;
    });
    var settled = false;
    try {
      final page = await AdminApi(origin.client).listFeedbackPage(
        status: nextStatus.isEmpty ? null : nextStatus,
        category: nextCategory.isEmpty ? null : nextCategory,
        query: nextQuery.isEmpty ? null : nextQuery,
        sort: nextSort,
        limit: nextPageSize,
        offset: nextOffset,
        isCurrent: current,
      );
      if (!current()) return false;
      final lastOffset = _lastAdminOffset(
        total: page.total,
        pageSize: nextPageSize,
      );
      if (page.items.isEmpty && nextOffset > 0 && lastOffset < nextOffset) {
        return await _load(
          origin: origin,
          offset: lastOffset,
          status: nextStatus,
          category: nextCategory,
          operation: operation,
          query: nextQuery,
          sort: nextSort,
          pageSize: nextPageSize,
        );
      }
      setState(() {
        _page = page;
        _items = page.items;
        _failedLoad = null;
      });
      settled = true;
      return true;
    } catch (error) {
      if (!current()) return false;
      setState(() {
        _error = error;
        _failedLoad = () async {
          await _load(
            origin: origin,
            offset: nextOffset,
            status: nextStatus,
            category: nextCategory,
            operation: null,
            query: nextQuery,
            sort: nextSort,
            pageSize: nextPageSize,
          );
        };
      });
      settled = true;
      return false;
    } finally {
      if (mounted && serial == _loadSerial) {
        setState(() {
          _loading = false;
          _readNeedsReload = !settled && _isActive;
        });
        if (_readNeedsReload) _deferLoad();
      }
    }
  }

  Widget _selector({
    Key? key,
    required String label,
    required String value,
    VoidCallback? onTap,
  }) => InkWell(
    key: key,
    borderRadius: BorderRadius.circular(16),
    onTap: onTap,
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        enabled: onTap != null,
        suffixIcon: const Icon(Icons.keyboard_arrow_down_rounded),
        isDense: true,
      ),
      child: Text(value),
    ),
  );

  bool _operationValid(_FeedbackOperation operation) =>
      identical(_operation, operation) &&
      _isCurrent(operation.origin, checkRoute: false);

  bool _operationCurrent(_FeedbackOperation operation) {
    if (!_operationValid(operation)) return false;
    final route = operation.selector ?? operation.dialog;
    return route == null
        ? _isCurrent(operation.origin)
        : route.isActive && route.isCurrent;
  }

  bool _modalCanEdit(_FeedbackOperation operation, Route<dynamic> route) =>
      route.isActive && route.isCurrent && _operationCurrent(operation);

  void _modalCovered(_FeedbackOperation operation, Route<dynamic> route) {
    if (!mounted || !identical(_operation, operation)) return;
    if (identical(route, operation.dialog) &&
        operation.selector?.isCurrent == true) {
      return;
    }
    _foregroundRevision++;
    _invalidate();
    _scheduleRebuild();
  }

  void _cancelDialog(BuildContext ctx, Route<dynamic> route) {
    if (ctx.mounted && route.isActive && route.isCurrent) {
      Navigator.of(ctx).pop();
    }
  }

  Future<T?> _dialog<T>(
    _FeedbackOperation operation,
    Widget Function(BuildContext, DialogRoute<T>) builder, {
    bool selector = false,
  }) async {
    if (!_operationCurrent(operation)) return null;
    late final DialogRoute<T> route;
    route = DialogRoute<T>(
      context: context,
      builder: (ctx) => AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: MediaQuery.removeViewInsets(
          context: ctx,
          removeBottom: true,
          child: _FeedbackModalGuard(
            onCovered: () => _modalCovered(operation, route),
            child: ValueListenableBuilder<int>(
              valueListenable: _uiRevision,
              builder: (ctx, _, _) => ValueListenableBuilder<int>(
                valueListenable: widget.activationRevision,
                builder: (ctx, _, _) => ValueListenableBuilder<AppLocale>(
                  valueListenable: I18n.localeListenable,
                  builder: (ctx, _, _) {
                    ModalRoute.isCurrentOf(ctx);
                    ctx.watch<AuthProvider?>();
                    ctx.watch<AppLockProvider?>();
                    ctx.watch<AppUpdateService?>();
                    if (!_operationValid(operation)) {
                      return AppDialog(
                        title: Text(AdminFeedbackUiCopy.expiredTitleFor()),
                        content: Text(AdminFeedbackUiCopy.expiredBodyFor()),
                        actions: [
                          TextButton(
                            onPressed: () => _cancelDialog(ctx, route),
                            child: Text(AdminUiCopy.closeFor()),
                          ),
                        ],
                      );
                    }
                    return builder(ctx, route);
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (selector) {
      operation.selector = route;
    } else {
      operation.dialog = route;
    }
    var pushed = false;
    try {
      pushed = true;
      final result = await Navigator.of(context).push(route);
      await route.completed;
      if (selector && identical(operation.selector, route)) {
        operation.selector = null;
        if (mounted) _uiRevision.value++;
      }
      if (!selector && identical(operation.dialog, route)) {
        operation.dialog = null;
      }
      return _operationCurrent(operation) ? result : null;
    } finally {
      if (pushed) await route.completed;
      if (identical(operation.selector, route)) operation.selector = null;
      if (identical(operation.dialog, route)) operation.dialog = null;
    }
  }

  Future<void> _withOperation(
    _FeedbackAction origin,
    String Function([AppLocale?]) action,
    Future<void> Function(_FeedbackOperation) body,
  ) async {
    if (_readBusy || _operation != null || !_isCurrent(origin)) return;
    final operation = _FeedbackOperation(origin);
    setState(() => _operation = operation);
    try {
      await body(operation);
    } on AdminActionExpired {
      // The original operation has no authority over the current page.
    } catch (error) {
      if (_operationCurrent(operation)) {
        _notice(
          origin,
          (locale) => AdminUiCopy.formatActionError(
            error,
            action(locale),
            locale: locale,
          ),
        );
      }
    } finally {
      if (mounted && identical(_operation, operation)) {
        setState(() => _operation = null);
        _deferLoad();
      }
    }
  }

  void _notice(_FeedbackAction origin, String Function(AppLocale) text) {
    if (!_isCurrent(origin)) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: ValueListenableBuilder<int>(
          valueListenable: _uiRevision,
          builder: (ctx, _, _) => ValueListenableBuilder<AppLocale>(
            valueListenable: I18n.localeListenable,
            builder: (ctx, locale, _) {
              ctx.watch<AuthProvider?>();
              ctx.watch<AppLockProvider?>();
              ctx.watch<AppUpdateService?>();
              return _isCurrent(origin)
                  ? Text(text(locale))
                  : const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
  }

  Future<void> _mutate(
    _FeedbackOperation operation,
    Future<void> Function(AdminApi, bool Function()) send,
    String Function(AppLocale) success, {
    int? offset,
  }) async {
    bool current() => _operationCurrent(operation);
    if (!current()) return;
    await send(AdminApi(operation.origin.client), current);
    if (!current()) return;
    final refreshed = await _load(
      origin: operation.origin,
      operation: operation,
      offset: offset ?? _offset,
    );
    if (!current()) return;
    _notice(
      operation.origin,
      (locale) => refreshed
          ? success(locale)
          : AdminFeedbackUiCopy.refreshFailed(success(locale), locale),
    );
  }

  Future<T?> _select<T>(
    _FeedbackOperation operation, {
    required String Function([AppLocale?]) title,
    required T selected,
    required List<T> options,
    required String Function(T, AppLocale?) label,
    bool nested = false,
  }) => _dialog<T>(
    operation,
    (ctx, route) => AppDialog(
      key: const ValueKey('admin_feedback_picker'),
      title: Text(title()),
      content: _adminDialogForm(
        maxWidth: 420,
        children: [
          for (final value in options)
            Semantics(
              selected: value == selected,
              button: true,
              child: ListTile(
                leading: Icon(
                  value == selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: Text(label(value, I18n.current)),
                onTap: () {
                  if (_modalCanEdit(operation, route)) {
                    Navigator.of(ctx).pop(value);
                  }
                },
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => _cancelDialog(ctx, route),
          child: Text(AdminUiCopy.cancelFor()),
        ),
      ],
    ),
    selector: nested,
  );

  Future<void> _pick<T>(
    _FeedbackAction origin, {
    required String Function([AppLocale?]) title,
    required T selected,
    required List<T> options,
    required String Function(T, AppLocale?) label,
    required Future<bool> Function(_FeedbackOperation, T) apply,
  }) => _withOperation(origin, title, (operation) async {
    final result = await _select<T>(
      operation,
      title: title,
      selected: selected,
      options: options,
      label: label,
    );
    if (result != null && _operationCurrent(operation)) {
      await apply(operation, result);
    }
  });

  Future<bool> _confirm(
    _FeedbackOperation operation, {
    required String Function([AppLocale?]) title,
    required String Function(AppLocale) message,
    required String Function([AppLocale?]) confirm,
  }) async =>
      await _dialog<bool>(
        operation,
        (ctx, route) => AppDialog(
          title: Text(title()),
          content: SingleChildScrollView(child: Text(message(I18n.current))),
          actions: [
            TextButton(
              onPressed: () => _cancelDialog(ctx, route),
              child: Text(AdminUiCopy.cancelFor()),
            ),
            FilledButton(
              onPressed: () {
                if (_modalCanEdit(operation, route)) {
                  Navigator.of(ctx).pop(true);
                }
              },
              child: Text(confirm()),
            ),
          ],
        ),
      ) ==
      true;

  Future<void> _reply(_FeedbackAction origin, Map<String, dynamic> item) =>
      _withOperation(
        origin,
        AdminFeedbackUiCopy.replyTitleFor,
        (operation) => _editReply(operation, Map.of(item)),
      );

  Future<void> _editReply(
    _FeedbackOperation operation,
    Map<String, dynamic> item,
  ) async {
    final controller = TextEditingController(
      text: (item['admin_reply'] ?? '').toString(),
    );
    var status = (item['status'] ?? 'resolved').toString();
    try {
      final saved = await _dialog<bool>(
        operation,
        (ctx, route) => StatefulBuilder(
          builder: (ctx, setFormState) => AppDialog(
            key: const ValueKey('admin_feedback_reply_dialog'),
            title: Text(AdminFeedbackUiCopy.replyTitleFor()),
            icon: const Icon(Icons.reply_outlined),
            content: _adminDialogForm(
              maxWidth: 560,
              children: [
                Text(
                  (item['content'] ?? '').toString(),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('admin_feedback_reply_field'),
                  enabled: _modalCanEdit(operation, route),
                  controller: controller,
                  maxLines: 4,
                  maxLength: 2000,
                  decoration: InputDecoration(
                    labelText: AdminFeedbackUiCopy.replyFieldFor(),
                  ),
                ),
                const SizedBox(height: 8),
                _selector(
                  key: const ValueKey('admin_feedback_reply_status'),

                  label: AdminFeedbackUiCopy.statusFieldFor(),
                  value: AdminFeedbackUiCopy.statusLabel(status),
                  onTap: () async {
                    if (!_modalCanEdit(operation, route)) return;
                    final picked = await _select<String>(
                      operation,
                      title: AdminFeedbackUiCopy.statusFieldFor,
                      selected: status,
                      options: [
                        if (!const [
                          'open',
                          'in_progress',
                          'resolved',
                          'closed',
                        ].contains(status))
                          status,
                        'open',
                        'in_progress',
                        'resolved',
                        'closed',
                      ],
                      label: AdminFeedbackUiCopy.statusLabel,
                      nested: true,
                    );
                    if (picked != null &&
                        ctx.mounted &&
                        _modalCanEdit(operation, route)) {
                      setFormState(() => status = picked);
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => _cancelDialog(ctx, route),
                child: Text(AdminUiCopy.cancelFor()),
              ),
              FilledButton(
                onPressed: () {
                  if (_modalCanEdit(operation, route)) {
                    Navigator.of(ctx).pop(true);
                  }
                },
                child: Text(AdminFeedbackUiCopy.submitFor()),
              ),
            ],
          ),
        ),
      );
      if (saved != true || !_operationCurrent(operation)) return;
      final id = (item['id'] as num).toInt();
      final reply = controller.text.trim();
      final submittedStatus = status;
      await _mutate(
        operation,
        (api, current) => api.replyFeedback(
          feedbackId: id,
          reply: reply,
          status: submittedStatus,
          isCurrent: current,
        ),
        (locale) => AdminFeedbackUiCopy.repliedFor(locale),
      );
    } finally {
      // _dialog has already waited for this exact route's exit animation.
      controller.dispose();
    }
  }

  Future<void> _showFeedbackDetail(
    _FeedbackAction origin,
    Map<String, dynamic> feedback,
  ) => _withOperation(origin, AdminFeedbackUiCopy.detailTitleFor, (
    operation,
  ) async {
    final summary = Map<String, dynamic>.from(feedback);
    final id = (summary['id'] as num?)?.toInt();
    Future<Map<String, dynamic>>? detailFuture;
    final reply = await _dialog<Map<String, dynamic>>(operation, (ctx, route) {
      detailFuture ??= id == null
          ? Future.value(summary)
          : AdminApi(origin.client)
                .getFeedbackDetail(
                  id,
                  isCurrent: () => _modalCanEdit(operation, route),
                )
                .then((remote) => <String, dynamic>{...summary, ...remote});
      return FutureBuilder<Map<String, dynamic>>(
        future: detailFuture,
        initialData: summary,
        builder: (ctx, snapshot) {
          if (!_modalCanEdit(operation, route)) return const SizedBox.shrink();
          final detail = snapshot.data ?? summary;
          final username = (detail['username'] ?? '').toString();
          final displayName = (detail['display_name'] ?? '').toString();
          final email = (detail['email'] ?? '').toString();
          final user = displayName.trim().isNotEmpty ? displayName : username;
          final identity = [
            if (username.isNotEmpty && username != user) '@$username',
            if (email.isNotEmpty)
              AdminFeedbackUiCopy.email(
                email,
                AdminFeedbackUiCopy.isEmailVerified(detail['email_verified']),
              ),
          ].join(' · ');
          final loading = snapshot.connectionState != ConnectionState.done;
          final adminReply = (detail['admin_reply'] ?? '').toString();
          return AppDialog(
            key: const ValueKey('admin_feedback_detail_dialog'),
            maxWidth: 720,
            icon: const Icon(Icons.feedback_outlined),
            title: Text(AdminFeedbackUiCopy.detailTitleFor()),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640, maxHeight: 520),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (loading) ...[
                      const LinearProgressIndicator(minHeight: 2),
                      const SizedBox(height: 12),
                    ],
                    if (snapshot.hasError) ...[
                      Text(
                        AdminFeedbackUiCopy.detailFailure(
                          userVisibleApiError(snapshot.error!),
                          I18n.current,
                        ),
                        style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: Theme.of(ctx).colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    _AdminFeedbackDetailField(
                      label: AdminFeedbackUiCopy.userFor(),
                      value: user.isEmpty
                          ? AdminFeedbackUiCopy.anonymousFor()
                          : user,
                    ),
                    if (identity.isNotEmpty)
                      _AdminFeedbackDetailField(
                        label: AdminFeedbackUiCopy.accountFor(),
                        value: identity,
                      ),
                    _AdminFeedbackDetailField(
                      label: AdminFeedbackUiCopy.categoryFor(),
                      value: _feedbackCategoryLabel(
                        (detail['category'] ?? '').toString(),
                      ),
                    ),
                    _AdminFeedbackDetailField(
                      label: AdminFeedbackUiCopy.statusFor(),
                      value: AdminFeedbackUiCopy.statusLabel(
                        (detail['status'] ?? 'open').toString(),
                      ),
                    ),
                    if ((detail['created_at'] ?? '').toString().isNotEmpty)
                      _AdminFeedbackDetailField(
                        label: AdminFeedbackUiCopy.createdFor(),
                        value: detail['created_at'].toString(),
                      ),
                    if ((detail['updated_at'] ?? '').toString().isNotEmpty)
                      _AdminFeedbackDetailField(
                        label: AdminFeedbackUiCopy.updatedFor(),
                        value: detail['updated_at'].toString(),
                      ),
                    _AdminFeedbackDetailField(
                      label: AdminFeedbackUiCopy.contentFor(),
                      value: (detail['content'] ?? '').toString(),
                      multiline: true,
                    ),
                    if (adminReply.isNotEmpty)
                      _AdminFeedbackDetailField(
                        label: AdminFeedbackUiCopy.adminReplyFor(),
                        value: adminReply,
                        multiline: true,
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => _cancelDialog(ctx, route),
                child: Text(AdminUiCopy.closeFor()),
              ),
              FilledButton(
                onPressed: () {
                  if (_modalCanEdit(operation, route)) {
                    Navigator.of(ctx).pop(Map<String, dynamic>.from(detail));
                  }
                },
                child: Text(AdminFeedbackUiCopy.replyFor()),
              ),
            ],
          );
        },
      );
    });
    if (reply != null && _operationCurrent(operation)) {
      await _editReply(operation, reply);
    }
  });

  Future<void> _deleteFeedback(
    _FeedbackAction origin,
    Map<String, dynamic> item,
    String user,
  ) => _withOperation(origin, AdminUiCopy.deleteFor, (operation) async {
    final id = (item['id'] as num).toInt();
    final offset = _offsetAfterAdminDelete(
      offset: _offset,
      itemCount: _items.length,
      pageSize: _pageSize,
    );
    if (!await _confirm(
      operation,
      title: AdminFeedbackUiCopy.deleteTitleFor,
      message: (locale) => AdminFeedbackUiCopy.deleteMessage(user, locale),
      confirm: AdminUiCopy.deleteFor,
    )) {
      return;
    }
    await _mutate(
      operation,
      (api, current) => api.deleteFeedback(id, isCurrent: current),
      (locale) => AdminFeedbackUiCopy.deletedFor(locale),
      offset: offset,
    );
  });

  Future<void> _closeFeedback(
    _FeedbackAction origin,
    Map<String, dynamic> item,
    String user,
  ) => _withOperation(origin, AdminUiCopy.closeFor, (operation) async {
    final id = (item['id'] as num).toInt();
    final existingReply = (item['admin_reply'] ?? '').toString().trim();
    final reply = existingReply.isEmpty ? '已关闭。' : existingReply;
    if (!await _confirm(
      operation,
      title: AdminFeedbackUiCopy.closeTitleFor,
      message: (locale) => AdminFeedbackUiCopy.closeMessage(user, locale),
      confirm: AdminUiCopy.closeFor,
    )) {
      return;
    }
    await _mutate(
      operation,
      (api, current) => api.closeFeedback(id, reply: reply, isCurrent: current),
      (locale) => AdminFeedbackUiCopy.closedFor(locale),
    );
  });

  List<int> _currentPageIdsWithStatus(String status) => _items
      .where((item) => (item['status'] ?? 'open').toString() == status)
      .map((item) => (item['id'] as num).toInt())
      .toList();

  Map<String, int> get _currentPageStatusCounts {
    final counts = <String, int>{};
    for (final item in _items) {
      final status = (item['status'] ?? 'open').toString();
      counts[status] = (counts[status] ?? 0) + 1;
    }
    return counts;
  }

  Future<void> _bulkUpdateCurrentPageStatus(
    _FeedbackAction origin, {
    required List<int> ids,
    required String toStatus,
    required String reply,
  }) => _withOperation(origin, AdminFeedbackUiCopy.bulkTitleFor, (
    operation,
  ) async {
    final submittedIds = List<int>.unmodifiable(ids);
    if (submittedIds.isEmpty) return;
    if (submittedIds.length > 100) {
      _notice(origin, (locale) => AdminFeedbackUiCopy.bulkLimitFor(locale));
      return;
    }
    if (!await _confirm(
      operation,
      title: AdminFeedbackUiCopy.bulkTitleFor,
      message: (locale) => AdminFeedbackUiCopy.bulkMessage(
        submittedIds.length,
        toStatus,
        locale,
      ),
      confirm: AdminFeedbackUiCopy.submitFor,
    )) {
      return;
    }
    await _mutate(
      operation,
      (api, current) => api.bulkUpdateFeedbackStatus(
        feedbackIds: submittedIds,
        reply: reply,
        status: toStatus,
        isCurrent: current,
      ),
      (locale) =>
          AdminFeedbackUiCopy.bulkSaved(submittedIds.length, toStatus, locale),
    );
  });

  Future<void> _exportFilteredCsv(_FeedbackAction origin) => _withOperation(
    origin,
    AdminFeedbackUiCopy.exportFor,
    (operation) async {
      bool current() => _operationCurrent(operation);
      final effects = widget.exportEffects;
      final csv = await AdminApi(origin.client).exportFeedbackCsv(
        status: _filter.isEmpty ? null : _filter,
        query: _query.isEmpty ? null : _query,
        category: _categoryFilter.isEmpty ? null : _categoryFilter,
        sort: _sort,
        isCurrent: current,
      );
      if (!current()) return;
      final path = await exportAdminFeedbackCsv(
        csv: csv,
        isCurrent: current,
        effects: effects,
        shareText: AdminFeedbackUiCopy.exportShareTextFor,
        shareSubject: AdminFeedbackUiCopy.exportSubjectFor,
      );
      if (current()) {
        _notice(origin, (locale) => AdminFeedbackUiCopy.exported(path, locale));
      }
    },
  );

  Widget _pagination(_FeedbackAction origin) {
    final compact = MediaQuery.sizeOf(context).width < 720;
    final busy = _readBusy || _operation != null;
    final totalPages = _adminTotalPages(_page, _pageSize);
    final currentPage = _page == null || totalPages == 0
        ? 0
        : (_page!.offset ~/ (_page!.limit <= 0 ? _pageSize : _page!.limit)) + 1;
    return Padding(
      key: const ValueKey('admin_feedback_pagination'),
      padding: compact
          ? const EdgeInsets.symmetric(horizontal: 16, vertical: 4)
          : const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_adminPageSummary(_page)} · ${_adminPageNumber(_page)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          SizedBox(height: compact ? 4 : 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton.icon(
                onPressed: busy
                    ? null
                    : () => _pick<int>(
                        origin,
                        title: AdminUiCopy.perPageFor,
                        selected: _pageSize,
                        options: _adminPageSizeOptions,
                        label: (value, _) => '$value',
                        apply: (op, value) => _load(
                          origin: op.origin,
                          operation: op,
                          pageSize: value,
                          offset: 0,
                        ),
                      ),
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                label: Text('${AdminUiCopy.perPageFor()}: $_pageSize'),
              ),
              if (!compact && totalPages > 1 && totalPages <= 200)
                TextButton.icon(
                  onPressed: busy
                      ? null
                      : () => _pick<int>(
                          origin,
                          title: AdminUiCopy.pageNumberFor,
                          selected: currentPage,
                          options: List.generate(totalPages, (i) => i + 1),
                          label: (value, _) => '$value/$totalPages',
                          apply: (op, value) => _load(
                            origin: op.origin,
                            operation: op,
                            offset: (value - 1) * _pageSize,
                          ),
                        ),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  label: Text(
                    '${AdminUiCopy.pageNumberFor()}: $currentPage/$totalPages',
                  ),
                ),
              if (!compact && totalPages > 1)
                IconButton(
                  tooltip: AdminUiCopy.jumpToFirstPageFor(),
                  onPressed: busy || (_page?.offset ?? 0) <= 0
                      ? null
                      : () => _load(origin: origin, offset: 0),
                  icon: const Icon(Icons.first_page),
                ),
              IconButton(
                tooltip: AdminUiCopy.previousPageFor(),
                onPressed: busy || (_page?.offset ?? 0) <= 0
                    ? null
                    : () => _load(
                        origin: origin,
                        offset: _previousAdminOffset(_offset, _pageSize),
                      ),
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                tooltip: AdminUiCopy.nextPageFor(),
                onPressed: busy || !(_page?.hasMore ?? false)
                    ? null
                    : () => _load(origin: origin, offset: _offset + _pageSize),
                icon: const Icon(Icons.chevron_right),
              ),
              if (!compact && totalPages > 1)
                IconButton(
                  tooltip: AdminUiCopy.jumpToLastPageFor(),
                  onPressed: busy || !(_page?.hasMore ?? false)
                      ? null
                      : () => _load(
                          origin: origin,
                          offset: _lastAdminOffset(
                            total: _page!.total,
                            pageSize: _pageSize,
                          ),
                        ),
                  icon: const Icon(Icons.last_page),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summary(_FeedbackAction origin) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final transitions = [
      ('open', 'in_progress', '已收到，进入处理中。'),
      ('in_progress', 'resolved', '已处理完成。'),
      ('resolved', 'closed', '已归档关闭。'),
    ];
    final counts = _currentPageStatusCounts;
    final oversized = transitions.any((t) => (counts[t.$1] ?? 0) > 100);
    return AppSurfaceCard(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 8),
      border: _adminSubtleListBorder(context),
      elevation: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AdminFeedbackUiCopy.summary(_items.length, counts),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.normal,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            AdminFeedbackUiCopy.summaryHint(
              _page?.total ?? _items.length,
              _sort,
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          if (oversized)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                AdminFeedbackUiCopy.bulkLimitFor(),
                style: theme.textTheme.bodySmall,
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              IconButton(
                tooltip: AdminFeedbackUiCopy.exportFor(),
                onPressed: _readBusy || _operation != null
                    ? null
                    : () => _exportFilteredCsv(origin),
                icon: const Icon(Icons.download_outlined),
              ),
              for (final t in transitions)
                if ((counts[t.$1] ?? 0) > 0)
                  TextButton.icon(
                    onPressed:
                        _readBusy ||
                            _operation != null ||
                            (counts[t.$1] ?? 0) > 100
                        ? null
                        : () => _bulkUpdateCurrentPageStatus(
                            origin,
                            ids: _currentPageIdsWithStatus(t.$1),
                            toStatus: t.$2,
                            reply: t.$3,
                          ),
                    icon: Icon(
                      t.$2 == 'in_progress'
                          ? Icons.playlist_add_check_outlined
                          : t.$2 == 'resolved'
                          ? Icons.task_alt_outlined
                          : Icons.inventory_2_outlined,
                    ),
                    label: Text(AdminFeedbackUiCopy.bulkLabel(t.$1, t.$2)),
                  ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final origin = _capture();
    if (!_isCurrent(origin, checkRoute: false)) {
      return const SizedBox.shrink();
    }
    final busy = _readBusy || _operation != null;
    final loadingFirstPage = _readBusy && _page == null;
    final compact = MediaQuery.sizeOf(context).width < 720;
    return RefreshIndicator(
      onRefresh: () async {
        if (_isCurrent(origin) && !busy) await _load(origin: origin);
      },
      child: CustomScrollView(
        key: const ValueKey('admin_feedback_scroll'),
        controller: _scrollCtrl,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppSectionHeader(
                  title: AdminFeedbackUiCopy.titleFor(),
                  subtitle: _adminPageSummary(_page),
                  actionLabel: AdminUiCopy.refreshFor(),
                  actionIcon: Icons.refresh,
                  onAction: busy ? null : () => _load(origin: origin),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    key: const ValueKey('admin_feedback_search'),
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: AdminFeedbackUiCopy.searchHintFor(),
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: AdminFeedbackUiCopy.clearSearchFor(),
                              icon: const Icon(Icons.close),
                              onPressed: busy
                                  ? null
                                  : () {
                                      if (!_isCurrent(origin)) return;
                                      _searchCtrl.clear();
                                      _load(
                                        origin: origin,
                                        query: '',
                                        offset: 0,
                                      );
                                    },
                            ),
                      isDense: true,
                    ),
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) {
                      if (!busy && _isCurrent(origin)) {
                        _load(
                          origin: origin,
                          query: _searchCtrl.text.trim(),
                          offset: 0,
                        );
                      }
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final value in [
                        '',
                        'open',
                        'in_progress',
                        'resolved',
                        'closed',
                      ])
                        ChoiceChip(
                          key: ValueKey('admin_feedback_status_$value'),
                          selected: _filter == value,
                          label: Text(
                            value.isEmpty
                                ? AdminFeedbackUiCopy.allStatusesFor()
                                : AdminFeedbackUiCopy.statusLabel(value),
                          ),
                          onSelected: busy
                              ? null
                              : (_) => _load(
                                  origin: origin,
                                  status: value,
                                  offset: 0,
                                ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final value in [
                        '',
                        'feature',
                        'bug',
                        'wish',
                        'other',
                      ])
                        ChoiceChip(
                          key: ValueKey('admin_feedback_category_$value'),
                          selected: _categoryFilter == value,
                          label: Text(_feedbackCategoryLabel(value)),
                          onSelected: busy
                              ? null
                              : (_) => _load(
                                  origin: origin,
                                  category: value,
                                  offset: 0,
                                ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: _selector(
                    key: const ValueKey('admin_feedback_sort'),
                    label: AdminFeedbackUiCopy.sortTitleFor(),
                    value: _adminFeedbackSortLabel(_sort),
                    onTap: busy
                        ? null
                        : () => _pick<String>(
                            origin,
                            title: AdminFeedbackUiCopy.sortTitleFor,
                            selected: _sort,
                            options: const [
                              'created_desc',
                              'updated_desc',
                              'status_asc',
                              'user_asc',
                            ],
                            label: _adminFeedbackSortLabel,
                            apply: (op, value) => _load(
                              origin: op.origin,
                              operation: op,
                              sort: value,
                              offset: 0,
                            ),
                          ),
                  ),
                ),
                _AdminInlineLoadingIndicator(
                  visible: _loading && _page != null,
                  label: AdminFeedbackUiCopy.updatingFor(),
                ),
              ],
            ),
          ),
          if (loadingFirstPage)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 12),
                    Text(AdminFeedbackUiCopy.loadingFor()),
                  ],
                ),
              ),
            )
          else if (_error != null)
            SliverToBoxAdapter(
              child: _AdminErrorState(
                message: _adminErrorMessage(
                  _error!,
                  AdminFeedbackUiCopy.titleFor(),
                ),
                onRetry: busy ? () async {} : _failedLoad ?? () async {},
              ),
            )
          else if (_items.isEmpty)
            SliverToBoxAdapter(
              child: EmptyState(
                icon: Icons.inbox_outlined,
                message:
                    _query.isEmpty && _filter.isEmpty && _categoryFilter.isEmpty
                    ? AdminFeedbackUiCopy.emptyFor()
                    : AdminFeedbackUiCopy.noMatchesFor(),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              sliver: SliverList.builder(
                itemCount: _items.length + (compact ? 0 : 1),
                itemBuilder: (ctx, index) => !compact && index == 0
                    ? _summary(origin)
                    : _feedbackCard(
                        ctx,
                        origin,
                        _items[index - (compact ? 0 : 1)],
                      ),
              ),
            ),
          SliverToBoxAdapter(child: _pagination(origin)),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  Widget _feedbackCard(
    BuildContext context,
    _FeedbackAction origin,
    Map<String, dynamic> item,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final status = (item['status'] ?? 'open').toString();
    final category = (item['category'] ?? '').toString();
    final username = (item['username'] ?? '').toString();
    final displayName = (item['display_name'] ?? '').toString();
    final user = displayName.trim().isNotEmpty ? displayName : username;
    final userLabel = user.isEmpty ? AdminFeedbackUiCopy.anonymousFor() : user;
    final email = (item['email'] ?? '').toString();
    final identity = [
      if (username.isNotEmpty && username != user) '@$username',
      if (email.isNotEmpty)
        AdminFeedbackUiCopy.email(
          email,
          AdminFeedbackUiCopy.isEmailVerified(item['email_verified']),
        ),
    ].join(' · ');
    final createdAt = (item['created_at'] ?? '').toString();
    final meta = [
      if (createdAt.isNotEmpty) createdAt,
      if (identity.isNotEmpty) identity,
    ].join(' · ');
    final reply = (item['admin_reply'] ?? '').toString();
    final color = switch (status) {
      'resolved' => Colors.green,
      'closed' => Colors.grey,
      'in_progress' => Colors.orange,
      _ => cs.primary,
    };
    final feedbackCard = AppSurfaceCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      border: _adminSubtleListBorder(context),
      elevation: 0,
      onTap: () => unawaited(_showFeedbackDetail(origin, Map.of(item))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '$userLabel · ${_feedbackCategoryLabel(category)}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.normal,
                ),
              ),
              AppStatusBadge(
                label: AdminFeedbackUiCopy.statusLabel(status),
                color: color,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              ),
            ],
          ),
          if (meta.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Text(
                meta,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          Text(
            (item['content'] ?? '').toString(),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurface.withValues(alpha: 0.7),
            ),
          ),
          if (reply.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.teal.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.teal.withValues(alpha: 0.16),
                    width: 0.45,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.subdirectory_arrow_right,
                      size: 16,
                      color: Colors.teal,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        AdminFeedbackUiCopy.replyPreview(reply),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
    return _AdminFeedbackSwipeActions(
      key: ValueKey('admin_feedback_swipe_${item['id']}'),
      isCurrent: () => !_readBusy && _operation == null && _isCurrent(origin),
      onDetail: () => unawaited(_showFeedbackDetail(origin, Map.of(item))),
      onClose: () => _closeFeedback(origin, Map.of(item), userLabel),
      onReply: () => _reply(origin, Map.of(item)),
      onDelete: () => _deleteFeedback(origin, Map.of(item), userLabel),
      child: feedbackCard,
    );
  }
}

class _AdminFeedbackDetailField extends StatelessWidget {
  final String label;
  final String value;
  final bool multiline;

  const _AdminFeedbackDetailField({
    required this.label,
    required this.value,
    this.multiline = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: appSecondaryControlLabelStyle(
              context,
            ).copyWith(color: cs.onSurface.withValues(alpha: 0.58)),
          ),
          const SizedBox(height: 4),
          SelectionArea(
            child: Text(
              value,
              softWrap: true,
              overflow: TextOverflow.visible,
              style:
                  (multiline
                          ? theme.textTheme.bodyMedium
                          : theme.textTheme.bodySmall)
                      ?.copyWith(
                        color: cs.onSurface.withValues(
                          alpha: multiline ? 0.82 : 0.7,
                        ),
                        height: multiline ? 1.35 : 1.28,
                        fontWeight: FontWeight.normal,
                      ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminFeedbackSwipeActions extends StatefulWidget {
  final Widget child;
  final bool Function() isCurrent;
  final VoidCallback onDetail;
  final Future<void> Function() onClose;
  final Future<void> Function() onReply;
  final Future<void> Function() onDelete;

  const _AdminFeedbackSwipeActions({
    super.key,
    required this.child,
    required this.isCurrent,
    required this.onDetail,
    required this.onClose,
    required this.onReply,
    required this.onDelete,
  });

  @override
  State<_AdminFeedbackSwipeActions> createState() =>
      _AdminFeedbackSwipeActionsState();
}

class _AdminFeedbackSwipeActionsState
    extends State<_AdminFeedbackSwipeActions> {
  static const double _actionRailWidth = 160;
  static const double _dragOpenThreshold = 40;
  double _dragDistance = 0;
  bool _open = false;

  void _setOpen(bool value) {
    if (_open == value) return;
    setState(() => _open = value);
  }

  void _resetDragDistance() {
    _dragDistance = 0;
  }

  Future<void> _runAction(
    Future<void> Function() action,
    bool Function() isCurrent,
  ) async {
    if (!isCurrent()) return;
    _setOpen(false);
    await action();
  }

  void _showDetail(VoidCallback action, bool Function() isCurrent) {
    if (!isCurrent()) return;
    _setOpen(false);
    action();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isCurrent = widget.isCurrent;
    final onDetail = widget.onDetail;
    final onReply = widget.onReply;
    final onClose = widget.onClose;
    final onDelete = widget.onDelete;
    return ClipRect(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) {
          if (isCurrent()) _resetDragDistance();
        },
        onHorizontalDragUpdate: (details) {
          if (!isCurrent()) return;
          _dragDistance += details.delta.dx;
          if (_dragDistance <= -_dragOpenThreshold) _setOpen(true);
          if (_dragDistance >= _dragOpenThreshold) _setOpen(false);
        },
        onHorizontalDragEnd: (details) {
          if (!isCurrent()) return;
          final velocity = details.primaryVelocity ?? 0;
          if (velocity < -120) _setOpen(true);
          if (velocity > 120) _setOpen(false);
          _resetDragDistance();
        },
        child: Stack(
          fit: StackFit.passthrough,
          clipBehavior: Clip.hardEdge,
          children: [
            if (_open)
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.only(right: 4, bottom: 8),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      width: _actionRailWidth,
                      height: 42,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest.withValues(
                            alpha: 0.94,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: cs.outlineVariant.withValues(alpha: 0.18),
                            width: 0.45,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: cs.shadow.withValues(alpha: 0.04),
                              blurRadius: 7,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _AdminFeedbackSwipeButton(
                              tooltip: AdminFeedbackUiCopy.detailTooltipFor(),
                              icon: Icons.visibility_outlined,
                              color: cs.primary,
                              onPressed: () => _showDetail(onDetail, isCurrent),
                            ),
                            const SizedBox(width: 4),
                            _AdminFeedbackSwipeButton(
                              tooltip: AdminFeedbackUiCopy.replyFor(),
                              icon: Icons.reply_outlined,
                              color: cs.tertiary,
                              onPressed: () =>
                                  unawaited(_runAction(onReply, isCurrent)),
                            ),
                            const SizedBox(width: 4),
                            _AdminFeedbackSwipeButton(
                              tooltip: AdminUiCopy.closeFor(),
                              icon: Icons.inventory_2_outlined,
                              color: cs.secondary,
                              onPressed: () =>
                                  unawaited(_runAction(onClose, isCurrent)),
                            ),
                            const SizedBox(width: 4),
                            _AdminFeedbackSwipeButton(
                              tooltip: AdminUiCopy.deleteFor(),
                              icon: Icons.delete_outline,
                              color: cs.error,
                              onPressed: () =>
                                  unawaited(_runAction(onDelete, isCurrent)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            TweenAnimationBuilder<double>(
              tween: Tween<double>(end: _open ? -_actionRailWidth : 0),
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              builder: (context, dx, child) =>
                  Transform.translate(offset: Offset(dx, 0), child: child),
              child: widget.child,
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminFeedbackSwipeButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  const _AdminFeedbackSwipeButton({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color.withValues(alpha: 0.12),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox.square(
            dimension: 36,
            child: Icon(icon, size: 17, color: color),
          ),
        ),
      ),
    );
  }
}

// ====================================================================
// 邀请码
// ====================================================================

class _InviteAction {
  _InviteAction(this.authority, this.view) : _viewRevision = view.value;

  final AdminActionOrigin authority;
  final ValueListenable<int> view;
  final int _viewRevision;

  ApiClient get client => authority.client;

  bool isCurrent({bool checkRoute = true}) =>
      view.value == _viewRevision &&
      authority.isCurrent(checkRoute: checkRoute);
}

class _InvitesTab extends StatefulWidget {
  final AdminApi api;
  final bool isActive;
  final ValueListenable<int> activationRevision;

  const _InvitesTab({
    super.key,
    required this.api,
    required this.isActive,
    required this.activationRevision,
  });

  @override
  State<_InvitesTab> createState() => _InvitesTabState();
}

class _InvitesTabState extends State<_InvitesTab> {
  final _actionHost = AdminActionHost();
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _codes = [];
  AdminPage? _page;
  bool _loading = true;
  bool _readNeedsReload = false;
  Object? _error;
  Object? _pendingMutation;
  String _status = '';
  String _query = '';
  String _sort = 'created_desc';
  int _pageSize = _adminPageSize;
  int _offset = 0;
  int _loadSerial = 0;
  int? _authorityRevision;
  int? _viewRevision;
  Future<void> Function()? _failedLoad;
  Route<dynamic>? _sortMenuRoute;
  int? _sortMenuAuthorityRevision;
  int? _sortMenuViewRevision;

  bool get _mutationPending => _pendingMutation != null;
  bool get _readBusy => _loading || _readNeedsReload;

  _InviteAction _capture() => _InviteAction(
    _actionHost.capture(
      client: widget.api.client,
      anyOfPermissions: const {'invites'},
    ),
    widget.activationRevision,
  );

  bool _isCurrent(_InviteAction origin, {bool checkRoute = true}) =>
      mounted && widget.isActive && origin.isCurrent(checkRoute: checkRoute);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _actionHost.bind(context);
    _viewRevision ??= widget.activationRevision.value;
    final revision = _actionHost.revision;
    if (_authorityRevision == revision) {
      if (_readNeedsReload) {
        final origin = _capture();
        if (_isCurrent(origin)) {
          _readNeedsReload = false;
          _load(origin: origin);
        }
      }
      return;
    }
    _authorityRevision = revision;
    _loadSerial++;
    _codes = [];
    _page = null;
    _readNeedsReload = false;
    _error = null;
    _failedLoad = null;
    _pendingMutation = null;
    _status = '';
    _query = '';
    _sort = 'created_desc';
    _offset = 0;
    _searchCtrl.clear();
    final origin = _capture();
    if (_isCurrent(origin)) {
      _load(origin: origin);
    } else {
      // The new authority may arrive while an obsolete dialog covers the page.
      // Load with a fresh receipt when the page becomes current again.
      _readNeedsReload = widget.isActive;
      _loading = false;
    }
  }

  @override
  void didUpdateWidget(covariant _InvitesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    final revision = widget.activationRevision.value;
    if (oldWidget.isActive == widget.isActive && _viewRevision == revision) {
      return;
    }
    _viewRevision = revision;
    _readNeedsReload = false;
    final serial = ++_loadSerial;
    _failedLoad = null;
    _pendingMutation = null;
    _loading = false;
    if (widget.isActive) {
      final origin = _capture();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || serial != _loadSerial) return;
        if (_isCurrent(origin)) {
          _load(origin: origin);
        } else if (widget.isActive) {
          setState(() => _readNeedsReload = true);
        }
      });
    }
  }

  @override
  void dispose() {
    _loadSerial++;
    _actionHost.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<bool> _load({
    required _InviteAction origin,
    _InviteAction? mutationOrigin,
    int? offset,
    String? status,
    String? query,
    String? sort,
    int? pageSize,
  }) async {
    bool current() =>
        _isCurrent(origin) &&
        (mutationOrigin == null || _isCurrent(mutationOrigin));
    if (!current()) return false;
    final serial = ++_loadSerial;
    final nextOffset = offset ?? _offset;
    final nextStatus = status ?? _status;
    final nextQuery = query ?? _query;
    final nextSort = sort ?? _sort;
    final nextPageSize = pageSize ?? _pageSize;
    setState(() {
      _offset = nextOffset;
      _status = nextStatus;
      _query = nextQuery;
      _sort = nextSort;
      _pageSize = nextPageSize;
      _loading = true;
      _error = null;
      _readNeedsReload = false;
    });
    var settled = false;
    try {
      final page = await AdminApi(origin.client).listInviteCodesPage(
        query: nextQuery.isEmpty ? null : nextQuery,
        status: nextStatus.isEmpty ? null : nextStatus,
        sort: nextSort,
        limit: nextPageSize,
        offset: nextOffset,
        isCurrent: current,
      );
      if (!current() || serial != _loadSerial) return false;
      _page = page;
      _codes = page.items;
      _failedLoad = null;
      settled = true;
      return true;
    } catch (error) {
      if (!current() || serial != _loadSerial) return false;
      _error = error;
      settled = true;
      _failedLoad = () async {
        await _load(
          origin: origin,
          mutationOrigin: mutationOrigin,
          offset: nextOffset,
          status: nextStatus,
          query: nextQuery,
          sort: nextSort,
          pageSize: nextPageSize,
        );
      };
      return false;
    } finally {
      if (mounted && serial == _loadSerial) {
        setState(() {
          _loading = false;
          // A temporary overlay may invalidate this read. On returning to the
          // foreground, use a new receipt rather than presenting a false empty
          // state or reviving the discarded interaction.
          _readNeedsReload = !settled && mutationOrigin == null;
        });
      }
    }
  }

  void _showSnack(_InviteAction origin, String Function(AppLocale) copy) {
    if (!_isCurrent(origin)) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: _AdminFeedbackText(copy)));
  }

  bool _closeDialog(
    BuildContext ctx,
    ModalRoute<dynamic> route,
    _InviteAction origin,
    bool confirmed,
  ) {
    if (!ctx.mounted ||
        !route.isActive ||
        !route.isCurrent ||
        (confirmed && !_isCurrent(origin, checkRoute: false))) {
      return false;
    }
    Navigator.of(ctx).pop(confirmed);
    return true;
  }

  void _finishMutation(Object operation) {
    if (mounted && identical(operation, _pendingMutation)) {
      setState(() => _pendingMutation = null);
    }
  }

  Widget? _dialogIcon(BuildContext context, IconData icon) {
    final media = MediaQuery.of(context);
    if (media.size.width < 360 && media.textScaler.scale(16) >= 30) {
      return null;
    }
    return Icon(icon);
  }

  Future<void> _generate(_InviteAction origin) async {
    if (_readBusy || _mutationPending || !_isCurrent(origin)) return;
    final operation = Object();
    setState(() => _pendingMutation = operation);
    final noteCtrl = TextEditingController();
    var count = 5;
    DialogRoute<bool>? dialogRoute;
    var pushed = false;
    bool canEdit() =>
        _isCurrent(origin, checkRoute: false) &&
        dialogRoute?.isActive == true &&
        dialogRoute?.isCurrent == true;
    try {
      dialogRoute = DialogRoute<bool>(
        context: context,
        builder: (ctx) => ValueListenableBuilder<AppLocale>(
          valueListenable: I18n.localeListenable,
          builder: (ctx, locale, _) => StatefulBuilder(
            builder: (ctx, setSt) => AppDialog(
              title: Text(AdminInviteUiCopy.generateTitleFor(locale)),
              icon: _dialogIcon(ctx, Icons.vpn_key_outlined),
              content: _adminDialogForm(
                maxWidth: 430,
                children: [
                  Text('${AdminInviteUiCopy.quantityFor(locale)}: $count'),
                  Slider(
                    key: const ValueKey('admin_invites_count_slider'),
                    value: count.toDouble(),
                    min: 1,
                    max: 50,
                    divisions: 49,
                    label: '$count',
                    onChanged: (value) {
                      if (canEdit()) {
                        setSt(() => count = value.round().clamp(1, 50));
                      }
                    },
                  ),
                  TextField(
                    key: const ValueKey('admin_invites_note_field'),
                    controller: noteCtrl,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: AdminInviteUiCopy.noteFor(locale),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () =>
                      _closeDialog(ctx, dialogRoute!, origin, false),
                  child: Text(AdminUiCopy.cancelFor(locale)),
                ),
                FilledButton(
                  onPressed: () {
                    if (canEdit()) {
                      _closeDialog(ctx, dialogRoute!, origin, true);
                    }
                  },
                  child: Text(AdminInviteUiCopy.generateFor(locale)),
                ),
              ],
            ),
          ),
        ),
      );
      final result = Navigator.of(context).push(dialogRoute);
      pushed = true;
      final confirmed = await result;
      await dialogRoute.completed;
      if (confirmed != true || !_isCurrent(origin)) return;
      final codes = await AdminApi(origin.client).createInviteCodes(
        count: count,
        note: noteCtrl.text,
        isCurrent: () => _isCurrent(origin),
      );
      if (!_isCurrent(origin)) return;
      final reloaded = await _load(
        origin: _capture(),
        mutationOrigin: origin,
        offset: 0,
      );
      if (!_isCurrent(origin)) return;
      await _showGeneratedCodes(origin, codes, reloaded: reloaded);
    } catch (error) {
      _showSnack(
        origin,
        (locale) => _adminActionErrorMessage(
          error,
          AdminInviteUiCopy.generateActionFor(locale),
          locale,
        ),
      );
    } finally {
      if (pushed) await dialogRoute!.completed;
      noteCtrl.dispose();
      _finishMutation(operation);
    }
  }

  Future<void> _showGeneratedCodes(
    _InviteAction origin,
    List<String> codes, {
    required bool reloaded,
  }) async {
    if (!_isCurrent(origin)) return;
    var copying = false;
    DialogRoute<void>? dialogRoute;
    bool canCopy() =>
        _isCurrent(origin, checkRoute: false) &&
        dialogRoute?.isActive == true &&
        dialogRoute?.isCurrent == true;
    dialogRoute = DialogRoute<void>(
      context: context,
      builder: (ctx) => ValueListenableBuilder<AppLocale>(
        valueListenable: I18n.localeListenable,
        builder: (ctx, locale, _) => StatefulBuilder(
          builder: (ctx, setSt) => AppDialog(
            title: Text(AdminInviteUiCopy.generatedTitle(codes.length, locale)),
            icon: _dialogIcon(ctx, Icons.check_circle_outline),
            content: _adminDialogForm(
              maxWidth: 430,
              children: [
                if (codes.isEmpty)
                  Text(AdminInviteUiCopy.noCodesReturnedFor(locale))
                else
                  SelectableText(
                    key: const ValueKey('admin_invites_generated_codes'),
                    codes.join('\n'),
                    style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                if (!reloaded) Text(AdminInviteUiCopy.refreshFailedFor(locale)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  final route = dialogRoute;
                  if (ctx.mounted &&
                      route != null &&
                      route.isActive &&
                      route.isCurrent) {
                    Navigator.of(ctx).pop();
                  }
                },
                child: Text(AdminUiCopy.closeFor(locale)),
              ),
              if (codes.isNotEmpty)
                FilledButton(
                  onPressed: copying
                      ? null
                      : () async {
                          if (copying || !canCopy()) return;
                          setSt(() => copying = true);
                          try {
                            await Clipboard.setData(
                              ClipboardData(text: codes.join('\n')),
                            );
                            if (canCopy() && ctx.mounted) {
                              Navigator.of(ctx).pop();
                            }
                          } catch (error) {
                            if (canCopy() && ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                  content: _AdminFeedbackText(
                                    (locale) => _adminActionErrorMessage(
                                      error,
                                      AdminInviteUiCopy.copyActionFor(locale),
                                      locale,
                                    ),
                                  ),
                                ),
                              );
                            }
                          } finally {
                            if (ctx.mounted && dialogRoute!.isActive) {
                              setSt(() => copying = false);
                            }
                          }
                        },
                  child: Text(AdminInviteUiCopy.copyAndCloseFor(locale)),
                ),
            ],
          ),
        ),
      ),
    );
    await Navigator.of(context).push(dialogRoute);
    await dialogRoute.completed;
  }

  Future<void> _delete(_InviteAction origin, Map<String, dynamic> item) async {
    if (_readBusy ||
        _mutationPending ||
        !_isCurrent(origin) ||
        (item['used_by'] ?? '').toString().isNotEmpty) {
      return;
    }
    final operation = Object();
    setState(() => _pendingMutation = operation);
    final code = (item['code'] ?? '').toString();
    DialogRoute<bool>? dialogRoute;
    var pushed = false;
    try {
      dialogRoute = DialogRoute<bool>(
        context: context,
        builder: (ctx) => ValueListenableBuilder<AppLocale>(
          valueListenable: I18n.localeListenable,
          builder: (ctx, locale, _) => AppDialog(
            title: Text(AdminInviteUiCopy.deleteTitleFor(locale)),
            icon: _dialogIcon(ctx, Icons.delete_outline),
            content: Text(AdminInviteUiCopy.deleteBody(code, locale)),
            actions: [
              TextButton(
                onPressed: () => _closeDialog(ctx, dialogRoute!, origin, false),
                child: Text(AdminUiCopy.cancelFor(locale)),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                  foregroundColor: Theme.of(ctx).colorScheme.onError,
                ),
                onPressed: () => _closeDialog(ctx, dialogRoute!, origin, true),
                child: Text(AdminUiCopy.deleteFor(locale)),
              ),
            ],
          ),
        ),
      );
      final result = Navigator.of(context).push(dialogRoute);
      pushed = true;
      final confirmed = await result;
      await dialogRoute.completed;
      if (confirmed != true || !_isCurrent(origin)) return;
      await AdminApi(
        origin.client,
      ).deleteInviteCode(code, isCurrent: () => _isCurrent(origin));
      if (!_isCurrent(origin)) return;
      final reloaded = await _load(
        origin: _capture(),
        mutationOrigin: origin,
        offset: _offsetAfterAdminDelete(
          offset: _offset,
          itemCount: _codes.length,
          pageSize: _pageSize,
        ),
      );
      _showSnack(
        origin,
        (locale) => reloaded
            ? AdminInviteUiCopy.deletedFor(locale)
            : AdminInviteUiCopy.deleteRefreshFailedFor(locale),
      );
    } catch (error) {
      _showSnack(
        origin,
        (locale) => _adminActionErrorMessage(
          error,
          AdminInviteUiCopy.deleteActionFor(locale),
          locale,
        ),
      );
    } finally {
      if (pushed) await dialogRoute!.completed;
      _finishMutation(operation);
    }
  }

  @override
  Widget build(BuildContext context) {
    final origin = _capture();
    final authorityRevision = _actionHost.revision;
    final viewRevision = widget.activationRevision.value;
    bool canSelectSort() =>
        _isCurrent(origin, checkRoute: false) &&
        ((_sortMenuRoute?.isActive == true &&
                _sortMenuRoute?.isCurrent == true &&
                _sortMenuAuthorityRevision == authorityRevision &&
                _sortMenuViewRevision == viewRevision &&
                _actionHost.revision == authorityRevision &&
                widget.activationRevision.value == viewRevision) ||
            _isCurrent(origin));
    final theme = Theme.of(context);
    final failedLoad = _failedLoad;
    Future<void> retry() async {
      if (!_isCurrent(origin)) return;
      if (failedLoad != null) {
        await failedLoad();
      } else {
        await _load(origin: origin);
      }
    }

    final error = _error == null
        ? null
        : _adminErrorMessage(_error!, AdminInviteUiCopy.listTargetFor());
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              await _load(origin: origin);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                Text(
                  AdminInviteUiCopy.listTitleFor(),
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  _adminPageSummary(_page),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      key: const ValueKey('admin_invites_generate_button'),
                      onPressed: _readBusy || _mutationPending
                          ? null
                          : () => _generate(origin),
                      icon: const Icon(Icons.add),
                      label: Text(AdminInviteUiCopy.generateTitleFor()),
                    ),
                    TextButton.icon(
                      onPressed: _readBusy ? null : () => _load(origin: origin),
                      icon: const Icon(Icons.refresh),
                      label: Text(AdminUiCopy.refreshFor()),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: AdminInviteUiCopy.searchHintFor(),
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: AdminInviteUiCopy.clearSearchFor(),
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              if (!_isCurrent(origin)) return;
                              _searchCtrl.clear();
                              _load(origin: origin, query: '', offset: 0);
                            },
                          ),
                    isDense: true,
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) {
                    if (_isCurrent(origin)) {
                      _load(
                        origin: origin,
                        query: _searchCtrl.text.trim(),
                        offset: 0,
                      );
                    }
                  },
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final value in ['', 'unused', 'used'])
                      _inviteStatusChip(origin, value),
                  ],
                ),
                const SizedBox(height: 8),
                AppDropdownField<String>(
                  key: ValueKey(('admin-invites-sort', _authorityRevision)),
                  initialValue: _sort,
                  isInteractionAllowed: () => _isCurrent(origin),
                  isSelectionAllowed: canSelectSort,
                  onMenuRouteCreated: (route) {
                    if (!_isCurrent(origin, checkRoute: false)) return;
                    _sortMenuRoute = route;
                    _sortMenuAuthorityRevision = authorityRevision;
                    _sortMenuViewRevision = viewRevision;
                  },
                  labelText: AdminInviteUiCopy.sortTitleFor(),
                  items: [
                    for (final value in [
                      'created_desc',
                      'used_desc',
                      'code_asc',
                      'note_asc',
                    ])
                      DropdownMenuItem(
                        value: value,
                        child: _AdminFeedbackText(
                          (locale) => _adminInviteSortLabel(value, locale),
                        ),
                      ),
                  ],
                  onChanged: (value) => _load(
                    origin: origin,
                    sort: value ?? 'created_desc',
                    offset: 0,
                  ),
                ),
                const SizedBox(height: 12),
                _AdminInlineLoadingIndicator(
                  visible: _loading && _page != null,
                  label: AdminInviteUiCopy.updatingFor(),
                ),
                if (_readBusy && _page == null)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        if (_loading) ...[
                          const CircularProgressIndicator(),
                          const SizedBox(height: 12),
                        ],
                        Text(AdminInviteUiCopy.loadingFor()),
                      ],
                    ),
                  )
                else if (error != null)
                  _AdminErrorState(message: error, onRetry: retry)
                else if (_codes.isEmpty)
                  EmptyState(
                    icon: Icons.vpn_key_outlined,
                    message: _query.isEmpty && _status.isEmpty
                        ? AdminInviteUiCopy.emptyFor()
                        : AdminInviteUiCopy.noMatchesFor(),
                  )
                else
                  for (final item in _codes) _inviteCard(context, origin, item),
              ],
            ),
          ),
        ),
        _AdminPaginationBar(
          barKey: const ValueKey('admin_invites_pagination_bar'),
          page: _page,
          loading: _readBusy,
          pageSize: _pageSize,
          onPageSizeChanged: (value) =>
              _load(origin: origin, pageSize: value, offset: 0),
          onPrevious: () => _load(
            origin: origin,
            offset: _previousAdminOffset(_offset, _pageSize),
          ),
          onNext: () => _load(origin: origin, offset: _offset + _pageSize),
          onJumpToPage: (page) =>
              _load(origin: origin, offset: (page - 1) * _pageSize),
        ),
      ],
    );
  }

  Widget _inviteStatusChip(_InviteAction origin, String value) {
    return ChoiceChip(
      label: Text(switch (value) {
        'unused' => AdminInviteUiCopy.unusedFor(),
        'used' => AdminInviteUiCopy.usedFor(),
        _ => AdminInviteUiCopy.allFor(),
      }),
      selected: _status == value,
      onSelected: (_) => _load(origin: origin, status: value, offset: 0),
    );
  }

  Widget _inviteCard(
    BuildContext context,
    _InviteAction origin,
    Map<String, dynamic> item,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final used = (item['used_by'] ?? '').toString().isNotEmpty;
    final note = (item['note'] ?? '').toString();
    String timestamp(Object? value) {
      final text = (value ?? '').toString();
      final date = DateTime.tryParse(text);
      return date == null ? text : I18nDateFormat.shortDateTime(date);
    }

    return AppSurfaceCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      border: _adminSubtleListBorder(context),
      elevation: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            (item['code'] ?? '').toString(),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: 'monospace',
              fontWeight: FontWeight.normal,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AppStatusBadge(
                label: used
                    ? AdminInviteUiCopy.usedFor()
                    : AdminInviteUiCopy.unusedFor(),
                color: used ? cs.onSurfaceVariant : cs.primary,
              ),
              if (!used)
                IconButton(
                  tooltip: AdminInviteUiCopy.deleteTooltipFor(),
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _readBusy || _mutationPending
                      ? null
                      : () => _delete(origin, item),
                ),
            ],
          ),
          if (used)
            Text(
              AdminInviteUiCopy.usedBy(
                (item['used_by_name'] ?? item['used_by'] ?? '-').toString(),
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          if (used && item['used_at'] != null)
            Text(
              AdminInviteUiCopy.usedAt(timestamp(item['used_at'])),
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          Text(
            AdminInviteUiCopy.createdAt(timestamp(item['created_at'])),
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          if (note.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(note, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

// ====================================================================
// 审计日志
// ====================================================================

class _AuditAction {
  _AuditAction(this.authority, this.view, this.foreground)
    : _viewRevision = view.value,
      _foregroundRevision = foreground();

  final AdminActionOrigin authority;
  final ValueListenable<int> view;
  final int _viewRevision;
  final int Function() foreground;
  final int _foregroundRevision;

  ApiClient get client => authority.client;

  bool isCurrent({bool checkRoute = true}) =>
      view.value == _viewRevision &&
      foreground() == _foregroundRevision &&
      authority.isCurrent(checkRoute: checkRoute);
}

class _AuditPickerOperation {
  _AuditPickerOperation(this.origin);

  final _AuditAction origin;
  DialogRoute<dynamic>? route;
}

/// Observes coverage of this exact picker, including cover/return while its
/// parent Admin route remains covered throughout the entire interaction.
class _AuditPickerRouteGuard extends StatefulWidget {
  final VoidCallback onCovered;
  final Widget child;

  const _AuditPickerRouteGuard({required this.onCovered, required this.child});

  @override
  State<_AuditPickerRouteGuard> createState() => _AuditPickerRouteGuardState();
}

class _AuditPickerRouteGuardState extends State<_AuditPickerRouteGuard> {
  bool? _wasCurrent;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    final current = route?.isCurrent ?? true;
    if (_wasCurrent == true && !current && route?.isActive == true) {
      widget.onCovered();
    }
    _wasCurrent = current;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _AuditLogTab extends StatefulWidget {
  final AdminApi api;
  final bool Function() isActiveNow;
  final ValueListenable<int> activationRevision;

  const _AuditLogTab({
    super.key,
    required this.api,
    required this.isActiveNow,
    required this.activationRevision,
  });

  @override
  State<_AuditLogTab> createState() => _AuditLogTabState();
}

class _AuditLogTabState extends State<_AuditLogTab> {
  final _actionHost = AdminActionHost();
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<Map<String, dynamic>> _items = [];
  AdminPage? _page;
  Object? _error;
  Future<void> Function()? _failedLoad;
  bool _loading = false;
  bool _readNeedsReload = false;
  bool _loadScheduled = false;
  bool _rebuildScheduled = false;
  bool? _wasForeground;
  int _foregroundRevision = 0;
  _AuditPickerOperation? _picker;
  AppAccessRouteGate? _routeEvents;
  ModalRoute<dynamic>? _pageRoute;
  Route<dynamic>? _lastTopRoute;
  String _action = '';
  String _query = '';
  String _sort = 'created_desc';
  int _pageSize = _adminPageSize;
  int _offset = 0;
  int _loadSerial = 0;
  int? _authorityRevision;
  int? _viewRevision;

  bool get _readBusy => _loading || _readNeedsReload;
  bool get _isActive => widget.isActiveNow();

  @override
  void initState() {
    super.initState();
    _viewRevision = widget.activationRevision.value;
    widget.activationRevision.addListener(_onViewEvent);
  }

  // A tab can leave and return before TabBarView updates this child. Suspend
  // its read immediately and arrange recovery from a fresh receipt next frame.
  void _onViewEvent() {
    if (!mounted) return;
    final revision = widget.activationRevision.value;
    if (_viewRevision == revision) return;
    _viewRevision = revision;
    _invalidate();
    _scheduleRebuild();
    _deferLoad();
  }

  void _bindRouteEvents() {
    _pageRoute = ModalRoute.of(context);
    final observers = Navigator.of(context).widget.observers;
    AppAccessRouteGate? source;
    for (final observer in observers) {
      if (observer is AppAccessRouteGate) {
        source = observer;
        break;
      }
    }
    if (identical(source, _routeEvents)) return;
    _routeEvents?.routeRevision.removeListener(_onRouteEvent);
    _routeEvents = source;
    _lastTopRoute = source?.currentRoute;
    source?.routeRevision.addListener(_onRouteEvent);
  }

  void _onRouteEvent() {
    if (!mounted) return;
    final top = _routeEvents?.currentRoute;
    if (identical(top, _lastTopRoute)) return;
    _lastTopRoute = top;
    final foreground = identical(top, _pageRoute);
    _wasForeground = foreground;
    if (!foreground) {
      if (_picker != null && identical(top, _picker!.route)) {
        final needsReload = _loading || _readNeedsReload;
        _loadSerial++;
        _loading = false;
        _readNeedsReload = needsReload;
      } else {
        _foregroundRevision++;
        _invalidate();
      }
      _scheduleRebuild();
    } else if (_readNeedsReload) {
      _deferLoad();
    }
  }

  _AuditAction _capture() {
    _syncAuthority();
    return _AuditAction(
      _actionHost.capture(
        client: widget.api.client,
        anyOfPermissions: const {'audit'},
      ),
      widget.activationRevision,
      () => _foregroundRevision,
    );
  }

  bool _isCurrent(_AuditAction origin, {bool checkRoute = true}) {
    if (!mounted) return false;
    _syncAuthority();
    return _isActive && origin.isCurrent(checkRoute: checkRoute);
  }

  // A client token/base URL can change without a provider notification. Never
  // give the previous server's displayed data a receipt for the new authority.
  void _syncAuthority() {
    final revision = _actionHost.revision;
    if (_authorityRevision == revision) return;
    _authorityRevision = revision;
    _invalidate(clearPrivateData: true);
    _deferLoad();
  }

  void _invalidate({bool clearPrivateData = false}) {
    _loadSerial++;
    _loading = false;
    _readNeedsReload = _isActive;
    _failedLoad = null;
    if (!clearPrivateData) return;
    _items = [];
    _page = null;
    _error = null;
    _action = '';
    _query = '';
    _sort = 'created_desc';
    _pageSize = _adminPageSize;
    _offset = 0;
    _searchCtrl.clear();
    _scheduleRebuild();
  }

  void _scheduleRebuild() {
    if (!mounted || _rebuildScheduled) return;
    _rebuildScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rebuildScheduled = false;
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  // Route dependencies schedule this again when a covering route is removed.
  // Do not hold a receipt captured while the Admin page is underneath a route.
  void _deferLoad() {
    if (!mounted || !_isActive || _loadScheduled || _picker != null) {
      return;
    }
    _loadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadScheduled = false;
      if (!mounted ||
          !_isActive ||
          !_readNeedsReload ||
          _loading ||
          _picker != null) {
        return;
      }
      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent) return;
      final origin = _capture();
      if (_isCurrent(origin)) {
        unawaited(_load(origin: origin));
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _actionHost.bind(context);
    _bindRouteEvents();
    _viewRevision ??= widget.activationRevision.value;
    _syncAuthority();
    final foreground = ModalRoute.of(context)?.isCurrent ?? true;
    if (_wasForeground == true && !foreground) {
      if (_picker == null) {
        _foregroundRevision++;
        _invalidate();
      } else {
        // Suspend an in-flight read without revoking our own picker. Opening
        // and canceling a picker on settled data does not issue another GET.
        final needsReload = _loading || _readNeedsReload;
        _loadSerial++;
        _loading = false;
        _readNeedsReload = needsReload;
      }
    }
    _wasForeground = foreground;
    if (_readNeedsReload) _deferLoad();
  }

  @override
  void didUpdateWidget(covariant _AuditLogTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.activationRevision, widget.activationRevision)) {
      oldWidget.activationRevision.removeListener(_onViewEvent);
      widget.activationRevision.addListener(_onViewEvent);
      _viewRevision = null;
    }
    _syncAuthority();
    final revision = widget.activationRevision.value;
    // A revision already handled by the synchronous listener must not start
    // another read when TabBarView eventually updates its cached child.
    if (_viewRevision == revision) return;
    _viewRevision = revision;
    _invalidate();
    if (_isActive) _deferLoad();
  }

  @override
  void dispose() {
    _loadSerial++;
    widget.activationRevision.removeListener(_onViewEvent);
    _actionHost.dispose();
    _routeEvents?.routeRevision.removeListener(_onRouteEvent);
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<bool> _load({
    required _AuditAction origin,
    int? offset,
    String? action,
    String? query,
    String? sort,
    int? pageSize,
  }) async {
    if (!_isCurrent(origin)) return false;
    final serial = ++_loadSerial;
    bool current() => serial == _loadSerial && _isCurrent(origin);
    final nextOffset = offset ?? _offset;
    final nextAction = action ?? _action;
    final nextQuery = query ?? _query;
    final nextSort = sort ?? _sort;
    final nextPageSize = pageSize ?? _pageSize;
    setState(() {
      _offset = nextOffset;
      _action = nextAction;
      _query = nextQuery;
      _sort = nextSort;
      _pageSize = nextPageSize;
      _loading = true;
      _readNeedsReload = false;
      _error = null;
    });
    var settled = false;
    try {
      final page = await AdminApi(origin.client).auditLogPage(
        action: nextAction.isEmpty ? null : nextAction,
        query: nextQuery.isEmpty ? null : nextQuery,
        sort: nextSort,
        limit: nextPageSize,
        offset: nextOffset,
        isCurrent: current,
      );
      if (!current()) return false;
      setState(() {
        _page = page;
        _items = page.items;
        _failedLoad = null;
      });
      settled = true;
      return true;
    } catch (error) {
      if (!current()) return false;
      setState(() {
        _error = error;
        _failedLoad = () async {
          await _load(
            origin: origin,
            offset: nextOffset,
            action: nextAction,
            query: nextQuery,
            sort: nextSort,
            pageSize: nextPageSize,
          );
        };
      });
      settled = true;
      return false;
    } finally {
      if (mounted && serial == _loadSerial) {
        setState(() {
          _loading = false;
          _readNeedsReload = !settled && _isActive;
        });
        if (_readNeedsReload) _deferLoad();
      }
    }
  }

  bool _pickerCanEdit(_AuditPickerOperation operation) =>
      identical(_picker, operation) &&
      _isCurrent(operation.origin, checkRoute: false) &&
      operation.route?.isActive == true &&
      operation.route?.isCurrent == true;

  void _coverPicker(_AuditPickerOperation operation) {
    if (!mounted || !identical(_picker, operation)) return;
    _foregroundRevision++;
    _invalidate();
    _scheduleRebuild();
  }

  Future<void> _pick<T>(
    _AuditAction origin, {
    required String Function(AppLocale?) title,
    required T selected,
    required List<T> options,
    required String Function(T, AppLocale?) label,
    required Future<bool> Function(_AuditAction, T) apply,
  }) async {
    if (_readBusy || _picker != null || !_isCurrent(origin)) return;
    final operation = _AuditPickerOperation(_capture());
    setState(() => _picker = operation);
    final route = DialogRoute<T>(
      context: context,
      builder: (ctx) => _AuditPickerRouteGuard(
        onCovered: () => _coverPicker(operation),
        child: ValueListenableBuilder<AppLocale>(
          valueListenable: I18n.localeListenable,
          builder: (ctx, locale, _) => AppDialog(
            key: const ValueKey('admin_audit_picker'),
            title: Text(title(locale)),
            content: _adminDialogForm(
              maxWidth: 420,
              children: [
                for (final value in options)
                  Semantics(
                    selected: value == selected,
                    button: true,
                    child: ListTile(
                      leading: Icon(
                        value == selected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                      ),
                      title: Text(label(value, locale)),
                      onTap: () {
                        if (!_pickerCanEdit(operation) || !ctx.mounted) {
                          return;
                        }
                        Navigator.of(ctx).pop(value);
                      },
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  if (!ctx.mounted ||
                      operation.route?.isActive != true ||
                      operation.route?.isCurrent != true) {
                    return;
                  }
                  Navigator.of(ctx).pop();
                },
                child: Text(AdminUiCopy.cancelFor(locale)),
              ),
            ],
          ),
        ),
      ),
    );
    operation.route = route;
    var pushed = false;
    try {
      pushed = true;
      final picked = await Navigator.of(context).push(route);
      await route.completed;
      final current = _isCurrent(operation.origin);
      if (mounted && identical(_picker, operation)) {
        setState(() => _picker = null);
      }
      if (picked != null && current) {
        await apply(_capture(), picked);
      } else {
        _deferLoad();
      }
    } finally {
      if (pushed) await route.completed;
      if (mounted && identical(_picker, operation)) {
        setState(() => _picker = null);
        _deferLoad();
      }
    }
  }

  Widget _auditPagination(_AuditAction origin) {
    final busy = _readBusy || _picker != null;
    final totalPages = _adminTotalPages(_page, _pageSize);
    final currentPage = _page == null || totalPages == 0
        ? 0
        : (_page!.offset ~/ (_page!.limit <= 0 ? _pageSize : _page!.limit)) + 1;
    return Padding(
      key: const ValueKey('admin_audit_pagination_bar'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_adminPageSummary(_page)} · ${_adminPageNumber(_page)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton.icon(
                onPressed: busy
                    ? null
                    : () => _pick<int>(
                        origin,
                        title: AdminUiCopy.perPageFor,
                        selected: _pageSize,
                        options: _adminPageSizeOptions,
                        label: (value, _) => '$value',
                        apply: (origin, value) =>
                            _load(origin: origin, pageSize: value, offset: 0),
                      ),
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                label: Text(AdminAuditUiCopy.pageSize(_pageSize)),
              ),
              if (totalPages > 1 && totalPages <= 200)
                TextButton.icon(
                  onPressed: busy
                      ? null
                      : () => _pick<int>(
                          origin,
                          title: AdminUiCopy.pageNumberFor,
                          selected: currentPage,
                          options: List.generate(
                            totalPages,
                            (index) => index + 1,
                          ),
                          label: (value, _) => '$value/$totalPages',
                          apply: (origin, value) => _load(
                            origin: origin,
                            offset: (value - 1) * _pageSize,
                          ),
                        ),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  label: Text(
                    AdminAuditUiCopy.pageNumber(currentPage, totalPages),
                  ),
                ),
              if (totalPages > 1)
                IconButton(
                  tooltip: AdminUiCopy.jumpToFirstPageFor(),
                  onPressed: busy || (_page?.offset ?? 0) <= 0
                      ? null
                      : () => _load(origin: origin, offset: 0),
                  icon: const Icon(Icons.first_page),
                ),
              IconButton(
                tooltip: AdminUiCopy.previousPageFor(),
                onPressed: busy || (_page?.offset ?? 0) <= 0
                    ? null
                    : () => _load(
                        origin: origin,
                        offset: _previousAdminOffset(_offset, _pageSize),
                      ),
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                tooltip: AdminUiCopy.nextPageFor(),
                onPressed: busy || !(_page?.hasMore ?? false)
                    ? null
                    : () => _load(origin: origin, offset: _offset + _pageSize),
                icon: const Icon(Icons.chevron_right),
              ),
              if (totalPages > 1)
                IconButton(
                  tooltip: AdminUiCopy.jumpToLastPageFor(),
                  onPressed: busy || !(_page?.hasMore ?? false)
                      ? null
                      : () => _load(
                          origin: origin,
                          offset: _lastAdminOffset(
                            total: _page!.total,
                            pageSize: _pageSize,
                          ),
                        ),
                  icon: const Icon(Icons.last_page),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final origin = _capture();
    final failedLoad = _failedLoad;
    Future<void> retry() async {
      if (!_isCurrent(origin)) return;
      if (failedLoad != null) {
        await failedLoad();
      } else {
        await _load(origin: origin);
      }
    }

    final error = _error == null
        ? null
        : _adminErrorMessage(_error!, AdminAuditUiCopy.titleFor());
    return RefreshIndicator(
      onRefresh: () async {
        await _load(origin: origin);
      },
      child: CustomScrollView(
        key: const ValueKey('admin_audit_body_scroll'),
        controller: _scrollCtrl,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AdminAuditUiCopy.titleFor(),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _adminPageSummary(_page),
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _readBusy ? null : () => _load(origin: origin),
                    icon: const Icon(Icons.refresh),
                    label: Text(AdminUiCopy.refreshFor()),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const ValueKey('admin_audit_search'),
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: AdminAuditUiCopy.searchHintFor(),
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: AdminAuditUiCopy.clearSearchFor(),
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                if (!_isCurrent(origin)) return;
                                _searchCtrl.clear();
                                _load(origin: origin, query: '', offset: 0);
                              },
                            ),
                      isDense: true,
                    ),
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) {
                      if (!_isCurrent(origin)) return;
                      _load(
                        origin: origin,
                        query: _searchCtrl.text.trim(),
                        offset: 0,
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final value in [
                        '',
                        'user.update',
                        'announcement.update',
                        'feedback.reply',
                        'invite.create',
                      ])
                        ChoiceChip(
                          key: ValueKey('admin_audit_action_$value'),
                          label: Text(_auditActionLabel(value)),
                          selected: _action == value,
                          onSelected: (_) =>
                              _load(origin: origin, action: value, offset: 0),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    key: ValueKey(('admin-audit-sort', _authorityRevision)),
                    borderRadius: BorderRadius.circular(12),
                    onTap: _readBusy || _picker != null
                        ? null
                        : () => _pick<String>(
                            origin,
                            title: AdminAuditUiCopy.sortTitleFor,
                            selected: _sort,
                            options: const [
                              'created_desc',
                              'actor_asc',
                              'action_asc',
                              'target_asc',
                            ],
                            label: _adminAuditSortLabel,
                            apply: (origin, value) =>
                                _load(origin: origin, sort: value, offset: 0),
                          ),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: AdminAuditUiCopy.sortTitleFor(),
                        enabled: !_readBusy && _picker == null,
                      ),
                      child: Row(
                        children: [
                          Expanded(child: Text(_adminAuditSortLabel(_sort))),
                          const SizedBox(width: 8),
                          const Icon(Icons.keyboard_arrow_down_rounded),
                        ],
                      ),
                    ),
                  ),
                  _AdminInlineLoadingIndicator(
                    visible: _loading && _page != null,
                    label: AdminAuditUiCopy.updatingFor(),
                  ),
                ],
              ),
            ),
          ),
          if (_readBusy && _page == null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    if (_loading) ...[
                      const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                    ],
                    Text(AdminAuditUiCopy.loadingFor()),
                  ],
                ),
              ),
            )
          else if (error != null)
            SliverToBoxAdapter(
              child: _AdminErrorState(message: error, onRetry: retry),
            )
          else if (_items.isEmpty)
            SliverToBoxAdapter(
              child: EmptyState(
                icon: Icons.receipt_long_outlined,
                message: _query.isEmpty && _action.isEmpty
                    ? AdminAuditUiCopy.emptyFor()
                    : AdminAuditUiCopy.noMatchesFor(),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList.builder(
                itemCount: _items.length,
                itemBuilder: (context, index) =>
                    _auditCard(context, _items[index]),
              ),
            ),
          SliverToBoxAdapter(child: _auditPagination(origin)),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  Widget _auditCard(BuildContext context, Map<String, dynamic> item) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final action = (item['action'] ?? '').toString();
    final actor = (item['actor_name'] ?? item['actor'] ?? '-').toString();
    final target = (item['target'] ?? '').toString();
    final detail = (item['detail'] ?? '').toString();
    final createdAt = (item['created_at'] ?? '').toString();
    return AppSurfaceCard(
      key: ValueKey(('admin-audit-record', item['id'])),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      border: _adminSubtleListBorder(context),
      elevation: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.receipt_long_outlined, size: 20, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _auditActionLabel(action),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            AdminAuditUiCopy.actor(actor),
            style: theme.textTheme.bodySmall,
          ),
          if (createdAt.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              createdAt,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
          if (target.isNotEmpty) ...[
            const SizedBox(height: 6),
            SelectableText(
              AdminAuditUiCopy.target(target),
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (detail.isNotEmpty) ...[
            const SizedBox(height: 6),
            SelectableText(
              AdminAuditUiCopy.detail(detail),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
