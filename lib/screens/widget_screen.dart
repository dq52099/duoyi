import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/account_preference_writes.dart';
import '../core/calendar_date_navigation.dart';
import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../core/platform_info.dart';
import '../core/web_target.dart';
import '../core/widget_ui_copy.dart';
import '../models/pomodoro.dart';
import '../providers/anniversary_provider.dart';
import '../providers/app_lock_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/calendar_provider.dart';
import '../providers/countdown_provider.dart';
import '../providers/course_provider.dart';
import '../providers/diary_provider.dart';
import '../providers/goal_provider.dart';
import '../providers/habit_provider.dart';
import '../providers/note_provider.dart';
import '../providers/pomodoro_provider.dart';
import '../providers/preferences_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/todo_provider.dart';
import '../services/account_local_data_cleaner.dart';
import '../services/android_widget_manager.dart';
import '../services/app_update_service.dart';
import '../services/holiday_calendar.dart';
import '../services/home_widget_service.dart';
import '../services/widget_display_mode_store.dart';
import '../services/widget_focus_projection.dart';
import '../services/widget_habit_progress.dart';
import '../services/widget_schedule_projection.dart';
import '../widgets/brand_background.dart'
    show BrandBackground, BrandRouteSurface, LocaleStatePreservingRoute;
import '../widgets/controller_dialog.dart';
import '../widgets/surface_components.dart';
import 'calendar_screen.dart';
import 'theme_picker_screen.dart';

Widget _widgetFeedback(
  ValueGetter<String> message, {
  ValueGetter<String>? actionLabel,
  VoidCallback? onAction,
}) {
  return ValueListenableBuilder<AppLocale>(
    valueListenable: I18n.localeListenable,
    builder: (context, _, _) {
      if (actionLabel == null || onAction == null) return Text(message());
      final theme = Theme.of(context);
      final cs = theme.colorScheme;
      final snackBarBackground = Color.alphaBlend(
        theme.snackBarTheme.backgroundColor ??
            (theme.useMaterial3
                ? cs.inverseSurface
                : cs.surfaceContainerHighest),
        cs.surface,
      );
      final actionForeground = appReadableForeground(
        snackBarBackground,
        theme.snackBarTheme.actionTextColor ?? cs.primary,
      );
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message()),
          TextButton(
            key: const ValueKey('widget_style_retry'),
            style: TextButton.styleFrom(foregroundColor: actionForeground),
            onPressed: onAction,
            child: Text(actionLabel()),
          ),
        ],
      );
    },
  );
}

typedef _WidgetCategory = WidgetCategory;

extension _WidgetCategoryX on _WidgetCategory {
  String get label => WidgetUiCopy.categoryLabel(this);
}

Color _widgetCatalogAccentColor(ColorScheme cs, bool isDark, int slot) {
  final base = switch (slot % 3) {
    0 => cs.primary,
    1 => cs.secondary,
    _ => cs.tertiary,
  };
  final hsl = HSLColor.fromColor(base);
  final hue = (hsl.hue + slot * 28.0) % 360.0;
  final sat = hsl.saturation.clamp(0.45, 0.78).toDouble();
  final light = isDark
      ? hsl.lightness.clamp(0.62, 0.74).toDouble()
      : hsl.lightness.clamp(0.32, 0.44).toDouble();
  final candidate = HSLColor.fromAHSL(1.0, hue, sat, light).toColor();
  final pillBg = Color.alphaBlend(candidate.withValues(alpha: 0.10), cs.surface);
  return appReadableForeground(pillBg, candidate);
}

class _WidgetCatalogItem {
  final DuoyiWidgetKind kind;
  final _WidgetCategory category;
  final IconData icon;
  final int accentSlot;
  final Widget Function(WidgetDisplayMode mode, TargetPlatform platform)
  previewBuilder;

  const _WidgetCatalogItem({
    required this.kind,
    required this.category,
    required this.icon,
    required this.accentSlot,
    required this.previewBuilder,
  });

  Color colorFor(ColorScheme cs, bool isDark) =>
      _widgetCatalogAccentColor(cs, isDark, accentSlot);

  String get title => WidgetUiCopy.catalogTitle(kind);
  String get subtitle => WidgetUiCopy.catalogSubtitle(kind);
}

final List<_WidgetCatalogItem> _widgetCatalog = [
  _WidgetCatalogItem(
    kind: DuoyiWidgetKind.todo,
    category: _WidgetCategory.productivity,
    icon: Icons.checklist_rtl_outlined,
    accentSlot: 0,
    previewBuilder: (mode, platform) =>
        WidgetPreviewCard.todo(displayMode: mode, platformOverride: platform),
  ),
  _WidgetCatalogItem(
    kind: DuoyiWidgetKind.focus,
    category: _WidgetCategory.productivity,
    icon: Icons.timer_outlined,
    accentSlot: 1,
    previewBuilder: (mode, platform) =>
        WidgetPreviewCard.focus(displayMode: mode, platformOverride: platform),
  ),
  _WidgetCatalogItem(
    kind: DuoyiWidgetKind.habit,
    category: _WidgetCategory.life,
    icon: Icons.self_improvement_outlined,
    accentSlot: 2,
    previewBuilder: (mode, platform) =>
        WidgetPreviewCard.habit(displayMode: mode, platformOverride: platform),
  ),
  _WidgetCatalogItem(
    kind: DuoyiWidgetKind.calendar,
    category: _WidgetCategory.life,
    icon: Icons.calendar_month_outlined,
    accentSlot: 3,
    previewBuilder: (mode, platform) => WidgetPreviewCard.calendar(
      displayMode: mode,
      platformOverride: platform,
    ),
  ),
  _WidgetCatalogItem(
    kind: DuoyiWidgetKind.schedule,
    category: _WidgetCategory.productivity,
    icon: Icons.event_note_outlined,
    accentSlot: 4,
    previewBuilder: (mode, platform) => WidgetPreviewCard.schedule(
      displayMode: mode,
      platformOverride: platform,
    ),
  ),
  _WidgetCatalogItem(
    kind: DuoyiWidgetKind.goal,
    category: _WidgetCategory.productivity,
    icon: Icons.flag_outlined,
    accentSlot: 5,
    previewBuilder: (mode, platform) =>
        WidgetPreviewCard.goal(displayMode: mode, platformOverride: platform),
  ),
  _WidgetCatalogItem(
    kind: DuoyiWidgetKind.course,
    category: _WidgetCategory.productivity,
    icon: Icons.school_outlined,
    accentSlot: 6,
    previewBuilder: (mode, platform) =>
        WidgetPreviewCard.course(displayMode: mode, platformOverride: platform),
  ),
  _WidgetCatalogItem(
    kind: DuoyiWidgetKind.note,
    category: _WidgetCategory.life,
    icon: Icons.edit_note_outlined,
    accentSlot: 7,
    previewBuilder: (mode, platform) =>
        WidgetPreviewCard.note(displayMode: mode, platformOverride: platform),
  ),
  _WidgetCatalogItem(
    kind: DuoyiWidgetKind.anniversary,
    category: _WidgetCategory.life,
    icon: Icons.event_available_outlined,
    accentSlot: 8,
    previewBuilder: (mode, platform) => WidgetPreviewCard.anniversary(
      displayMode: mode,
      platformOverride: platform,
    ),
  ),
  _WidgetCatalogItem(
    kind: DuoyiWidgetKind.diary,
    category: _WidgetCategory.life,
    icon: Icons.book_outlined,
    accentSlot: 9,
    previewBuilder: (mode, platform) =>
        WidgetPreviewCard.diary(displayMode: mode, platformOverride: platform),
  ),
];

class WidgetScreen extends StatefulWidget
    implements LocaleStatePreservingRoute {
  const WidgetScreen({
    super.key,
    this.hostPlatform,
    this.isActive = true,
    this.activityRevision,
  });

  /// Allows embedding and fixtures to choose the host without changing globals.
  final WidgetHostPlatform? hostPlatform;
  final bool isActive;

  /// Invalidates retained actions even when the shell leaves and returns before
  /// Flutter builds an inactive frame.
  final ValueListenable<int>? activityRevision;

  @override
  State<WidgetScreen> createState() => _WidgetScreenState();
}

class _WidgetScreenState extends State<WidgetScreen>
    with WidgetsBindingObserver {
  WidgetHostPlatform get _hostPlatform =>
      widget.hostPlatform ??
      (kIsWeb
          ? WidgetHostPlatform.web
          : PlatformInfo.isIOS
          ? WidgetHostPlatform.ios
          : PlatformInfo.isAndroid
          ? WidgetHostPlatform.android
          : WidgetHostPlatform.desktop);
  WidgetDisplayMode _displayMode = WidgetDisplayMode.standard;
  AndroidWidgetPinResult? _pinSupport;
  bool _checkingPinSupport = true;
  bool _canOpenWidgetSettings = false;
  bool _refreshingData = false;
  _WidgetCategory _selectedCategory = _WidgetCategory.all;
  bool _useRealData = false;
  bool? _previewDarkOverride;
  bool _userChangedDisplayMode = false;
  int _pinSupportSeq = 0;
  int _displayModeSeq = 0;
  int _loadDisplayModeSeq = 0;
  int _refreshSeq = 0;
  bool _isUpdatingDisplayMode = false;
  bool _loadingDisplayMode = true;
  bool _displayModeLoadFailed = false;
  WidgetDisplayModeSelection? _displayModeSelection;

  bool get _displayModeSyncPending => _displayModeSelection?.pending ?? false;

  bool get _displayModeUnavailable =>
      _loadingDisplayMode ||
      _displayModeLoadFailed ||
      _isUpdatingDisplayMode ||
      (_refreshingData && _displayModeSyncPending);
  int _hostGeneration = 0;
  int _activityGeneration = 0;
  Object? _pinSupportOperation;
  final Set<DuoyiWidgetKind> _pendingPinRequests = {};

  @override
  void didUpdateWidget(covariant WidgetScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.activityRevision, widget.activityRevision)) {
      oldWidget.activityRevision?.removeListener(_invalidateActivity);
      widget.activityRevision?.addListener(_invalidateActivity);
      _invalidateActivity();
    }
    if (oldWidget.isActive != widget.isActive) _invalidateActivity();
    if (oldWidget.hostPlatform == widget.hostPlatform) return;
    _hostGeneration++;
    _pinSupportSeq++;
    _pinSupportOperation = null;
    _pinSupport = null;
    _checkingPinSupport = true;
    _canOpenWidgetSettings = false;
    _loadPinSupport();
  }

  void _invalidateActivity() {
    _activityGeneration++;
  }

  bool _beginPinRequest(DuoyiWidgetKind kind) {
    if (!mounted || _displayModeUnavailable || !_pendingPinRequests.add(kind)) {
      return false;
    }
    setState(() {});
    return true;
  }

  void _endPinRequest(DuoyiWidgetKind kind) {
    _pendingPinRequests.remove(kind);
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    widget.activityRevision?.addListener(_invalidateActivity);
    WidgetsBinding.instance.addObserver(this);
    I18n.localeListenable.addListener(_onLocaleChanged);
    AccountLocalDataCleaner.accountDataGenerationListenable.addListener(
      _onAccountDataChanged,
    );
    _loadDisplayMode();
    _loadPinSupport();
  }

  @override
  void dispose() {
    widget.activityRevision?.removeListener(_invalidateActivity);
    I18n.localeListenable.removeListener(_onLocaleChanged);
    AccountLocalDataCleaner.accountDataGenerationListenable.removeListener(
      _onAccountDataChanged,
    );
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onLocaleChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onAccountDataChanged() {
    if (!mounted) return;
    _displayModeSeq++;
    _loadDisplayModeSeq++;
    _refreshSeq++;
    _userChangedDisplayMode = false;
    _isUpdatingDisplayMode = false;
    _loadingDisplayMode = true;
    _displayModeLoadFailed = false;
    _displayModeSelection = null;
    _refreshingData = false;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    setState(() {
      _displayMode = WidgetDisplayMode.standard;
    });
    _loadDisplayMode();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadPinSupport();
    }
  }

  Future<void> _loadDisplayMode() async {
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final readSeq = ++_loadDisplayModeSeq;
    bool isCurrent() =>
        mounted &&
        readSeq == _loadDisplayModeSeq &&
        !_userChangedDisplayMode &&
        AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          accountGeneration,
        );
    try {
      final selection = await WidgetDisplayModeStore.read();
      if (!isCurrent()) return;
      setState(() {
        _displayModeSeq++;
        _displayModeSelection = selection;
        _displayMode = WidgetDisplayMode.fromId(selection.mode);
        _loadingDisplayMode = false;
        _displayModeLoadFailed = false;
      });
    } catch (_) {
      if (!isCurrent()) return;
      setState(() {
        _loadingDisplayMode = false;
        _displayModeLoadFailed = true;
      });
    }
  }

  void _retryDisplayModeLoad(_WidgetActionOrigin origin) {
    if (!mounted ||
        !_displayModeLoadFailed ||
        _loadingDisplayMode ||
        _isUpdatingDisplayMode ||
        !origin.isCurrent(context)) {
      return;
    }
    setState(() {
      _loadingDisplayMode = true;
      _displayModeLoadFailed = false;
    });
    _loadDisplayMode();
  }

  Future<void> _loadPinSupport() async {
    if (_hostPlatform != WidgetHostPlatform.android) {
      _pinSupportSeq++;
      if (!mounted) return;
      setState(() {
        _pinSupport = AndroidWidgetPinResult.unsupportedPlatform;
        _checkingPinSupport = false;
        _canOpenWidgetSettings = false;
      });
      return;
    }
    if (_pinSupportOperation != null || !mounted) return;
    final operation = Object();
    _pinSupportOperation = operation;
    final seq = ++_pinSupportSeq;
    setState(() => _checkingPinSupport = true);
    try {
      final support = await AndroidWidgetManager.checkPinSupport();
      if (!mounted ||
          seq != _pinSupportSeq ||
          _hostPlatform != WidgetHostPlatform.android) {
        return;
      }
      final canOpenSettings =
          await AndroidWidgetManager.canOpenWidgetSettings();
      if (!mounted ||
          seq != _pinSupportSeq ||
          _hostPlatform != WidgetHostPlatform.android) {
        return;
      }
      setState(() {
        _pinSupport = support;
        _checkingPinSupport = false;
        _canOpenWidgetSettings = canOpenSettings;
      });
    } finally {
      if (identical(_pinSupportOperation, operation)) {
        _pinSupportOperation = null;
      }
    }
  }

  Future<bool> _deliverDisplayMode(
    WidgetDisplayModeSelection selection, {
    required int homeWidgetAccountGeneration,
    required int preferenceGeneration,
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent()) return false;
    final synced = await HomeWidgetService.setDisplayMode(
      selection.mode,
      expectedAccountGeneration: homeWidgetAccountGeneration,
      expectedPreferenceGeneration: preferenceGeneration,
    );
    if (!synced || !isCurrent()) return false;
    return WidgetDisplayModeStore.acknowledge(selection, isCurrent: isCurrent);
  }

  Future<void> _setDisplayMode(
    WidgetDisplayMode mode,
    _WidgetActionOrigin origin, {
    WidgetDisplayModeSelection? retryIntent,
  }) async {
    if (!mounted ||
        _isUpdatingDisplayMode ||
        _refreshingData ||
        !origin.isCurrent(context) ||
        (retryIntent != null &&
            (!_displayModeSyncPending ||
                _displayModeSelection?.intentId != retryIntent.intentId))) {
      return;
    }
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    // Capture ownership before queueing, including work from another page.
    final homeGeneration = HomeWidgetService.accountGeneration;
    final preferenceGeneration = AccountPreferenceWrites.generation;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final seq = ++_displayModeSeq;
    bool isCurrent() =>
        mounted &&
        seq == _displayModeSeq &&
        origin.isAccountCurrent(context) &&
        homeGeneration == HomeWidgetService.accountGeneration &&
        preferenceGeneration == AccountPreferenceWrites.generation &&
        AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          accountGeneration,
        );
    _userChangedDisplayMode = true;
    setState(() {
      _displayMode = mode;
      _loadingDisplayMode = false;
      _displayModeLoadFailed = false;
      _isUpdatingDisplayMode = true;
    });

    void showFailure(WidgetDisplayModeSelection? intent) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: _widgetFeedback(
            () => WidgetUiCopy.styleSyncFailed,
            actionLabel: () => WidgetUiCopy.actionRetry,
            onAction: () {
              if (!isCurrent() || !origin.isCurrent(context)) return;
              _setDisplayMode(mode, origin, retryIntent: intent);
            },
          ),
        ),
      );
    }

    await WidgetDisplayModeStore.runOperation(() async {
      WidgetDisplayModeSelection? committed;
      try {
        if (!mounted || !isCurrent()) return;
        if (retryIntent == null) {
          committed = await WidgetDisplayModeStore.save(
            mode.id,
            isCurrent: isCurrent,
          );
        } else {
          final saved = await WidgetDisplayModeStore.read();
          if (!mounted || !isCurrent()) return;
          if (!saved.pending ||
              saved.intentId != retryIntent.intentId ||
              saved.mode != retryIntent.mode) {
            setState(() {
              _displayModeSelection = saved;
              _displayMode = WidgetDisplayMode.fromId(saved.mode);
            });
            return;
          }
          committed = saved;
        }
        if (!isCurrent()) return;
        if (committed == null) throw const AccountPreferenceWriteCanceled();
        final selection = committed;
        setState(() => _displayModeSelection = selection);
        final synced = await _deliverDisplayMode(
          selection,
          homeWidgetAccountGeneration: homeGeneration,
          preferenceGeneration: preferenceGeneration,
          isCurrent: isCurrent,
        );
        if (!mounted || !isCurrent()) return;
        // Re-read the durable record, including an acknowledgement that failed
        // after native delivery or a competing update with a newer identity.
        final saved = await WidgetDisplayModeStore.read();
        if (!mounted || !isCurrent()) return;
        setState(() {
          _displayModeSelection = saved;
          _displayMode = WidgetDisplayMode.fromId(saved.mode);
        });
        if (!mounted || !origin.isCurrent(context)) return;
        if (synced) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: _widgetFeedback(
                () => WidgetUiCopy.hostStyleSyncSuccess(
                  mode.label,
                  _hostPlatform,
                ),
              ),
            ),
          );
        } else {
          showFailure(selection);
        }
      } catch (_) {
        if (!mounted || !isCurrent()) return;
        try {
          final saved = await WidgetDisplayModeStore.read();
          if (!mounted || !isCurrent()) return;
          setState(() {
            _displayModeSelection = saved;
            _displayMode = WidgetDisplayMode.fromId(saved.mode);
            _userChangedDisplayMode = false;
          });
        } catch (_) {
          if (!mounted || !isCurrent()) return;
          setState(() {
            _displayModeSelection = null;
            _displayModeLoadFailed = true;
            _userChangedDisplayMode = false;
          });
        }
        if (mounted && isCurrent() && origin.isCurrent(context)) {
          showFailure(committed);
        }
      } finally {
        if (mounted && seq == _displayModeSeq) {
          setState(() => _isUpdatingDisplayMode = false);
        }
      }
    });
  }

  Future<void> _openWidgetSettings(_WidgetActionOrigin origin) async {
    if (!mounted ||
        _hostPlatform != WidgetHostPlatform.android ||
        !origin.isCurrent(context)) {
      return;
    }
    final opened = await AndroidWidgetManager.openWidgetSettings();
    if (!mounted || !origin.isCurrent(context)) return;
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: _widgetFeedback(() => WidgetUiCopy.cannotOpenSettings),
        ),
      );
    }
  }

  void _setPinSupport(AndroidWidgetPinResult support) {
    _pinSupportSeq++;
    if (!mounted) return;
    setState(() {
      _pinSupport = support;
      _checkingPinSupport = false;
    });
  }

  Future<void> _refreshWidgetData(_WidgetActionOrigin origin) async {
    if (_refreshingData ||
        _displayModeUnavailable ||
        !origin.isCurrent(context)) {
      return;
    }
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final preferenceGeneration = AccountPreferenceWrites.generation;
    final homeGeneration = HomeWidgetService.accountGeneration;
    final seq = ++_refreshSeq;
    var styleSeq = _displayModeSeq;
    bool isCurrent() =>
        mounted &&
        seq == _refreshSeq &&
        styleSeq == _displayModeSeq &&
        origin.isCurrent(context) &&
        preferenceGeneration == AccountPreferenceWrites.generation &&
        homeGeneration == HomeWidgetService.accountGeneration &&
        AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          accountGeneration,
        );
    var hadPendingRecovery = _displayModeSyncPending;
    setState(() {
      _refreshingData = true;
      // Invalidate unsent pin preflight before the first recovery await.
      if (_displayModeSyncPending) styleSeq = ++_displayModeSeq;
    });
    try {
      final styleSynced = await WidgetDisplayModeStore.runOperation(() async {
        if (!isCurrent()) return false;
        final saved = await WidgetDisplayModeStore.read();
        if (!isCurrent()) return false;
        if (saved.pending) hadPendingRecovery = true;
        setState(() {
          _displayModeSelection = saved;
          final mode = WidgetDisplayMode.fromId(saved.mode);
          if (saved.pending || mode != _displayMode) {
            styleSeq = ++_displayModeSeq;
          }
          _displayMode = mode;
        });
        // A page load or ordinary data refresh never reapplies an already
        // acknowledged/legacy mode, preserving per-instance pin choices.
        if (!saved.pending) return true;
        setState(() => _isUpdatingDisplayMode = true);
        final synced = await _deliverDisplayMode(
          saved,
          homeWidgetAccountGeneration: homeGeneration,
          preferenceGeneration: preferenceGeneration,
          isCurrent: isCurrent,
        );
        if (!isCurrent()) return false;
        final confirmed = await WidgetDisplayModeStore.read();
        if (!isCurrent()) return false;
        setState(() => _displayModeSelection = confirmed);
        return synced;
      });
      if (!mounted || !isCurrent()) return;
      final success =
          styleSynced && await HomeWidgetService.refreshDashboardData();
      if (!mounted || !isCurrent()) return;
      final messenger = ScaffoldMessenger.of(context);
      if (hadPendingRecovery && success) {
        messenger.removeCurrentSnackBar();
      }
      messenger.showSnackBar(
        SnackBar(
          content: _widgetFeedback(
            () => success
                ? WidgetUiCopy.refreshSuccess
                : WidgetUiCopy.refreshFailed,
          ),
        ),
      );
    } catch (_) {
      if (!mounted || !isCurrent()) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: _widgetFeedback(() => WidgetUiCopy.refreshFailed)),
      );
    } finally {
      if (mounted && seq == _refreshSeq) {
        setState(() {
          _refreshingData = false;
          _isUpdatingDisplayMode = false;
        });
      }
    }
  }

  Widget _buildPreviewToolbar(BuildContext context, bool isDark) {
    final themeProvider = _watchOptionalProvider<ThemeProvider>(context);
    final widgetBrandDark = themeProvider != null
        ? themeProvider.activeWidgetBackgroundBrand.theme.brightness ==
              Brightness.dark
        : isDark;
    final effectiveDark = _previewDarkOverride ?? widgetBrandDark;
    return _WidgetPreviewToolbar(
      useRealData: _useRealData,
      previewDark: effectiveDark,
      onDataSourceChanged: (realData) {
        if (_useRealData == realData) return;
        setState(() => _useRealData = realData);
      },
      onDarkPreviewChanged: (dark) {
        if (effectiveDark == dark && _previewDarkOverride != null) return;
        setState(() => _previewDarkOverride = dark);
      },
      onOpenThemeStudio: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const BrandRouteSurface(child: ThemePickerScreen()),
          ),
        );
      },
    );
  }

  Widget _buildCatalogCard(
    BuildContext context,
    _WidgetCatalogItem item,
    ColorScheme screenCs,
    bool isDark,
  ) {
    return RepaintBoundary(
      child: AppSurfaceCard(
        key: ValueKey('widget_gallery_${item.kind.name}'),
        padding: const EdgeInsets.all(DesignTokens.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _WidgetCatalogTile(
              icon: item.icon,
              title: item.title,
              subtitle: item.subtitle,
              color: item.colorFor(screenCs, isDark),
            ),
            const SizedBox(height: 10),
            item.previewBuilder(
              _displayMode,
              _hostPlatform == WidgetHostPlatform.android
                  ? TargetPlatform.android
                  : TargetPlatform.iOS,
            ),
            const SizedBox(height: 8),
            _AddWidgetButton(
              hostPlatform: _hostPlatform,
              isActive: widget.isActive,
              hostGeneration: _hostGeneration,
              activityGeneration: () => _activityGeneration,
              key: ValueKey(item.kind),
              requesting: _pendingPinRequests.contains(item.kind),
              beginRequest: () => _beginPinRequest(item.kind),
              endRequest: () => _endPinRequest(item.kind),
              pinSupport: _pinSupport,
              checkingPinSupport: _checkingPinSupport,
              kind: item.kind,
              displayMode: _displayMode,
              styleStatusLabel: _loadingDisplayMode
                  ? WidgetUiCopy.loadingStyle
                  : _displayModeLoadFailed
                  ? WidgetUiCopy.styleLoadFailed
                  : (_isUpdatingDisplayMode ||
                        (_refreshingData && _displayModeSyncPending))
                  ? WidgetUiCopy.updatingStyle
                  : null,
              styleRevision: _displayModeSeq,
              currentStyleRevision: () => _displayModeSeq,
              canOpenWidgetSettings: _canOpenWidgetSettings,
              onPinSupportChanged: _setPinSupport,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final retryIntent = _displayModeSelection;
    final hostGeneration = _hostGeneration;
    final activityGeneration = _activityGeneration;
    final wasActive = widget.isActive;
    final settingsOrigin = _WidgetActionOrigin.capture(
      context,
      isCallerAvailable: () =>
          mounted &&
          wasActive &&
          widget.isActive &&
          _activityGeneration == activityGeneration &&
          _hostGeneration == hostGeneration,
    );
    final routeBackground = Theme.of(context).scaffoldBackgroundColor;
    final surfaceStyle = appSurfaceStyleOf(context);
    final isLiquidGlass = surfaceStyle == AppSurfaceStyle.liquidGlass;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenCs = Theme.of(context).colorScheme;
    final filteredCatalog = _selectedCategory == _WidgetCategory.all
        ? _widgetCatalog
        : _widgetCatalog
              .where((item) => item.category == _selectedCategory)
              .toList();

    final scaffold = Scaffold(
      backgroundColor: isLiquidGlass ? Colors.transparent : routeBackground,
      appBar: AppBar(
        title: Text(WidgetUiCopy.screenTitle),
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
        backgroundColor: routeBackground.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
        actions: [
          if (_hostPlatform == WidgetHostPlatform.android ||
              _hostPlatform == WidgetHostPlatform.ios)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: WidgetUiCopy.refreshTooltip,
              onPressed: _refreshingData || _displayModeUnavailable
                  ? null
                  : () => _refreshWidgetData(settingsOrigin),
            ),
        ],
      ),
      body: _WidgetPreviewScope(
        darkOverride: _previewDarkOverride,
        useRealData: _useRealData,
        child: _WidgetGalleryFrame(
          child: AppSecondaryControlTheme(
            child: WebTarget.isDesktopWebBuild
                ? const _DesktopWebWidgetFallback()
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                    itemCount: 9 + filteredCatalog.length * 2,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return _WidgetDisplayModePanel(
                          hostPlatform: _hostPlatform,
                          value: _displayMode,
                          enabled: !_isUpdatingDisplayMode && !_refreshingData,
                          loading: _loadingDisplayMode,
                          loadFailed: _displayModeLoadFailed,
                          onReload: () => _retryDisplayModeLoad(settingsOrigin),
                          syncPending: _displayModeSyncPending,
                          syncing: _isUpdatingDisplayMode || _refreshingData,
                          onRetrySync: retryIntent == null
                              ? null
                              : () => _setDisplayMode(
                                  _displayMode,
                                  settingsOrigin,
                                  retryIntent: retryIntent,
                                ),
                          onChanged: _isUpdatingDisplayMode || _refreshingData
                              ? null
                              : (mode) => _setDisplayMode(mode, settingsOrigin),
                        );
                      }
                      if (index == 1) return const SizedBox(height: 12);
                      if (index == 2) {
                        return _WidgetPinSupportBanner(
                          hostPlatform: _hostPlatform,
                          result: _pinSupport,
                          checking: _checkingPinSupport,
                          canOpenSettings: _canOpenWidgetSettings,
                          onRefresh: () {
                            if (settingsOrigin.isCurrent(context)) {
                              _loadPinSupport();
                            }
                          },
                          onOpenSettings: () =>
                              _openWidgetSettings(settingsOrigin),
                        );
                      }
                      if (index == 3) return const SizedBox(height: 12);
                      if (index == 4) {
                        return _WidgetCategoryFilter(
                          selected: _selectedCategory,
                          onSelected: (category) {
                            setState(() => _selectedCategory = category);
                          },
                        );
                      }
                      if (filteredCatalog.isEmpty) {
                        if (index == 5) return const SizedBox(height: 12);
                        if (index == 6) {
                          return _buildPreviewToolbar(context, isDark);
                        }
                        if (index == 7) return const SizedBox(height: 16);
                        return AppInfoBanner(
                          icon: Icons.touch_app_outlined,
                          color: screenCs.primary,
                          title: WidgetUiCopy.widgetTipsBannerTitle,
                          message: WidgetUiCopy.hostTipsMessage(_hostPlatform),
                        );
                      }
                      if (index == 5) return const SizedBox(height: 16);
                      if (index == 6) {
                        return _buildCatalogCard(
                          context,
                          filteredCatalog.first,
                          screenCs,
                          isDark,
                        );
                      }
                      if (index == 7) return const SizedBox(height: 12);
                      if (index == 8) {
                        return _buildPreviewToolbar(context, isDark);
                      }
                      if (index == 7 + filteredCatalog.length * 2) {
                        return const SizedBox(height: 16);
                      }
                      if (index == 8 + filteredCatalog.length * 2) {
                        return AppInfoBanner(
                          icon: Icons.touch_app_outlined,
                          color: screenCs.primary,
                          title: WidgetUiCopy.widgetTipsBannerTitle,
                          message: WidgetUiCopy.hostTipsMessage(_hostPlatform),
                        );
                      }
                      final catalogIndex = (index - 9) ~/ 2 + 1;
                      if ((index - 9).isEven) {
                        return SizedBox(height: catalogIndex == 1 ? 12 : 16);
                      }
                      return _buildCatalogCard(
                        context,
                        filteredCatalog[catalogIndex],
                        screenCs,
                        isDark,
                      );
                    },
                  ),
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
  }
}

class _WidgetGalleryFrame extends StatelessWidget {
  const _WidgetGalleryFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: child,
    ),
  );
}

// Text applies this system accessibility preference at render time too.
TextStyle _widgetMeasurementStyle(BuildContext context, TextStyle style) {
  final inherited = DefaultTextStyle.of(context).style.merge(style);
  return inherited.copyWith(
    fontWeight: MediaQuery.boldTextOf(context)
        ? FontWeight.bold
        : inherited.fontWeight,
    height: MediaQuery.maybeLineHeightScaleFactorOverrideOf(context),
    letterSpacing: MediaQuery.maybeLetterSpacingOverrideOf(context),
    wordSpacing: MediaQuery.maybeWordSpacingOverrideOf(context),
  );
}

Axis _widgetSegmentDirection(
  BuildContext context,
  BoxConstraints constraints,
  Iterable<String> labels,
) {
  var widest = 0.0;
  final textStyle = _widgetMeasurementStyle(
    context,
    appSecondaryControlTextStyle(context),
  );
  for (final label in labels) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: textStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    if (painter.width > widest) widest = painter.width;
    painter.dispose();
  }
  // Flutter gives every horizontal segment the same width. Measuring the
  // longest label also protects languages with uneven label lengths.
  final requiredWidth = (widest + 36) * labels.length;
  return constraints.maxWidth < requiredWidth ? Axis.vertical : Axis.horizontal;
}

class _DesktopWebWidgetFallback extends StatelessWidget {
  const _DesktopWebWidgetFallback();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      key: const ValueKey('desktop_web_widget_fallback'),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
      children: [
        AppInfoBanner(
          icon: Icons.desktop_windows_outlined,
          color: cs.primary,
          title: WidgetUiCopy.desktopWebTitle,
          message: WidgetUiCopy.desktopWebMessage,
        ),
        const SizedBox(height: 12),
        _WidgetCatalogTile(
          icon: Icons.calendar_month_outlined,
          title: WidgetUiCopy.catalogTitle(DuoyiWidgetKind.calendar),
          subtitle: WidgetUiCopy.desktopWebTileSubtitle,
          color: cs.primary,
        ),
        const SizedBox(height: 10),
        const WidgetPreviewCard.calendar(
          displayMode: WidgetDisplayMode.detailed,
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const CalendarScreen())),
            style: appSecondaryFilledButtonStyle(context).copyWith(
              minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
              visualDensity: VisualDensity.standard,
            ),
            icon: const Icon(Icons.calendar_month_outlined, size: 18),
            label: Text(WidgetUiCopy.desktopWebOpenCalendar),
          ),
        ),
      ],
    );
  }
}

class _WidgetCategoryFilter extends StatelessWidget {
  final _WidgetCategory selected;
  final ValueChanged<_WidgetCategory> onSelected;

  const _WidgetCategoryFilter({
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final direction = _widgetSegmentDirection(
          context,
          constraints,
          _WidgetCategory.values.map((category) => category.label),
        );
        const segmentPadding = EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 4,
        );
        final segmentMinWidth =
            direction == Axis.vertical &&
                constraints.maxWidth > segmentPadding.horizontal
            ? constraints.maxWidth - segmentPadding.horizontal
            : 0.0;
        final segmented = SegmentedButton<_WidgetCategory>(
          direction: direction,
          style: ButtonStyle(
            textStyle: WidgetStatePropertyAll(
              appSecondaryControlTextStyle(context),
            ),
            visualDensity: VisualDensity(vertical: 1),
            shape: WidgetStatePropertyAll<OutlinedBorder>(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.all(
                  Radius.circular(
                    appSurfaceStyleOf(context)?.smallTileRadius ?? 10,
                  ),
                ),
              ),
            ),
            padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
              segmentPadding,
            ),
            tapTargetSize: MaterialTapTargetSize.padded,
          ),
          segments: [
            for (final cat in _WidgetCategory.values)
              ButtonSegment<_WidgetCategory>(
                value: cat,
                label: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: segmentMinWidth,
                    minHeight: 44,
                  ),
                  child: Center(
                    child: Text(
                      cat.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
          ],
          selected: {selected},
          showSelectedIcon: false,
          onSelectionChanged: (next) => onSelected(next.single),
        );
        return SizedBox(width: double.infinity, child: segmented);
      },
    );
  }
}

class _WidgetPreviewToolbar extends StatelessWidget {
  final bool useRealData;
  final bool previewDark;
  final ValueChanged<bool> onDataSourceChanged;
  final ValueChanged<bool> onDarkPreviewChanged;
  final VoidCallback onOpenThemeStudio;

  const _WidgetPreviewToolbar({
    required this.useRealData,
    required this.previewDark,
    required this.onDataSourceChanged,
    required this.onDarkPreviewChanged,
    required this.onOpenThemeStudio,
  });

  @override
  Widget build(BuildContext context) {
    final locale = I18n.current;
    final sampleLabel = switch (locale) {
      AppLocale.zh => '示例预览',
      AppLocale.en => 'Sample',
    };
    final realLabel = switch (locale) {
      AppLocale.zh => '实时数据',
      AppLocale.en => 'Live Data',
    };
    final lightLabel = switch (locale) {
      AppLocale.zh => '浅色',
      AppLocale.en => 'Light',
    };
    final darkLabel = switch (locale) {
      AppLocale.zh => '深色',
      AppLocale.en => 'Dark',
    };
    final studioLabel = switch (locale) {
      AppLocale.zh => '外观配色',
      AppLocale.en => 'Appearance',
    };
    return AppSurfaceCard(
      key: const ValueKey('widget_preview_toolbar'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _WidgetPreviewSegmentToggle(
            key: const ValueKey('widget_preview_data_toggle'),
            firstLabel: sampleLabel,
            secondLabel: realLabel,
            secondSelected: useRealData,
            onChanged: onDataSourceChanged,
          ),
          _WidgetPreviewSegmentToggle(
            key: const ValueKey('widget_preview_dark_toggle'),
            firstLabel: lightLabel,
            secondLabel: darkLabel,
            secondSelected: previewDark,
            onChanged: onDarkPreviewChanged,
          ),
          FilledButton.icon(
            key: const ValueKey('widget_open_theme_studio'),
            onPressed: onOpenThemeStudio,
            style: appSecondaryFilledButtonStyle(context).copyWith(
              minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
              visualDensity: VisualDensity.standard,
            ),
            icon: const Icon(Icons.palette_outlined, size: 17),
            label: Text(studioLabel),
          ),
        ],
      ),
    );
  }
}

class _WidgetPreviewSegmentToggle extends StatelessWidget {
  final String firstLabel;
  final String secondLabel;
  final bool secondSelected;
  final ValueChanged<bool> onChanged;

  const _WidgetPreviewSegmentToggle({
    super.key,
    required this.firstLabel,
    required this.secondLabel,
    required this.secondSelected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final surfaceStyle = appSurfaceStyleOf(context);
    final radius = surfaceStyle?.smallTileRadius ?? 10.0;
    final containerBg = cs.surface;
    return Material(
      type: MaterialType.transparency,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: containerBg,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.45),
            width: 0.5,
          ),
        ),
        child: Wrap(
          spacing: 4,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _SegmentChip(
              label: firstLabel,
              selected: !secondSelected,
              radius: radius - 2,
              onTap: () => onChanged(false),
            ),
            _SegmentChip(
              label: secondLabel,
              selected: secondSelected,
              radius: radius - 2,
              onTap: () => onChanged(true),
            ),
          ],
        ),
      ),
    );
  }
}

class _SegmentChip extends StatelessWidget {
  final String label;
  final bool selected;
  final double radius;
  final VoidCallback onTap;

  const _SegmentChip({
    required this.label,
    required this.selected,
    required this.radius,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final surfaceStyle = appSurfaceStyleOf(context);
    final cardBase = Color.alphaBlend(
      surfaceStyle?.cardFillColor ?? cs.surface,
      theme.scaffoldBackgroundColor,
    );
    final fill = selected
        ? Color.alphaBlend(cs.primary.withValues(alpha: 0.14), cs.surface)
        : cs.surface;
    final effectiveFill = Color.alphaBlend(fill, cardBase);
    final foreground = selected
        ? appReadableForeground(effectiveFill, cs.primary)
        : appReadableForeground(effectiveFill, cs.onSurfaceVariant);
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(radius),
          ),
          child: Align(
            alignment: Alignment.center,
            widthFactor: 1.0,
            heightFactor: 1.0,
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: foreground,
                fontWeight: FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WidgetPinSupportBanner extends StatelessWidget {
  final WidgetHostPlatform hostPlatform;
  final AndroidWidgetPinResult? result;
  final bool checking;
  final bool canOpenSettings;
  final VoidCallback onRefresh;
  final VoidCallback onOpenSettings;

  const _WidgetPinSupportBanner({
    required this.hostPlatform,
    required this.result,
    required this.checking,
    required this.canOpenSettings,
    required this.onRefresh,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final support = result;
    final manualHost = hostPlatform != WidgetHostPlatform.android;
    final supported = support == AndroidWidgetPinResult.requested;
    final blocked =
        support == AndroidWidgetPinResult.unsupportedLauncher ||
        support == AndroidWidgetPinResult.unsupportedPlatform ||
        support == AndroidWidgetPinResult.unavailable;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = manualHost
        ? cs.primary
        : checking
        ? cs.secondary
        : supported
        ? cs.primary
        : blocked
        ? cs.error
        : cs.secondary;
    final title = manualHost
        ? WidgetUiCopy.hostSupportTitle(hostPlatform)
        : checking
        ? WidgetUiCopy.pinSupportCheckingTitle
        : supported
        ? WidgetUiCopy.pinSupportSupportedTitle
        : WidgetUiCopy.pinSupportResultTitle(support);
    final message = manualHost
        ? WidgetUiCopy.hostSupportMessage(hostPlatform)
        : checking
        ? WidgetUiCopy.pinSupportCheckingMessage
        : supported
        ? WidgetUiCopy.pinSupportSupportedMessage
        : WidgetUiCopy.pinSupportResultMessage(support);
    final surfaceStyle = appSurfaceStyleOf(context);
    final iconRadius = surfaceStyle?.smallTileRadius ?? 10.0;
    final Color? actionForeground;
    if (surfaceStyle != null) {
      final routeBackground = Color.alphaBlend(
        theme.scaffoldBackgroundColor,
        cs.surface,
      );
      final cardBase = Color.alphaBlend(
        surfaceStyle.cardFillColor ?? cs.surface,
        routeBackground,
      );
      final bannerBackground = Color.alphaBlend(
        color.withValues(alpha: 0.08),
        cardBase,
      );
      actionForeground = appReadableForeground(bannerBackground, cs.primary);
    } else {
      actionForeground = null;
    }
    return AppSurfaceCard(
      padding: const EdgeInsets.all(12),
      color: color.withValues(alpha: 0.08),
      border: Border.all(color: color.withValues(alpha: 0.12), width: 0.45),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 600;
          final headerAndBody = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(iconRadius),
                ),
                child: Icon(
                  supported ? Icons.check_circle_outline : Icons.info_outline,
                  size: 18,
                  color: color,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      message,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.72),
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          final actions = Wrap(
            spacing: 8,
            runSpacing: 4,
            alignment: WrapAlignment.end,
            children: [
              if (!manualHost && canOpenSettings)
                TextButton.icon(
                  onPressed: checking ? null : onOpenSettings,
                  icon: const Icon(Icons.settings_outlined, size: 16),
                  label: Text(WidgetUiCopy.actionAppSettings),
                  style: TextButton.styleFrom(
                    foregroundColor: actionForeground,
                    iconColor: actionForeground,
                    visualDensity: VisualDensity.standard,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    minimumSize: const Size(44, 44),
                    textStyle: appSecondaryControlTextStyle(context),
                  ),
                ),
              if (!manualHost)
                TextButton.icon(
                  onPressed: checking ? null : onRefresh,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text(WidgetUiCopy.actionRecheck),
                  style: TextButton.styleFrom(
                    foregroundColor: actionForeground,
                    iconColor: actionForeground,
                    visualDensity: VisualDensity.standard,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    minimumSize: const Size(44, 44),
                    textStyle: appSecondaryControlTextStyle(context),
                  ),
                ),
            ],
          );

          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                headerAndBody,
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerRight, child: actions),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: headerAndBody),
              const SizedBox(width: 8),
              actions,
            ],
          );
        },
      ),
    );
  }
}

enum WidgetDisplayMode {
  compact('compact', '2x2', 1.0, 320),
  standard('standard', '3x2', 1.5, 480),
  detailed('detailed', '4x3', 4 / 3, 640);

  final String id;
  final String previewCellLabel;
  final double previewAspectRatio;
  final double previewMaxWidth;

  const WidgetDisplayMode(
    this.id,
    this.previewCellLabel,
    this.previewAspectRatio,
    this.previewMaxWidth,
  );

  static WidgetDisplayMode fromId(String? id) {
    return WidgetDisplayMode.values.firstWhere(
      (mode) => mode.id == id,
      orElse: () => WidgetDisplayMode.standard,
    );
  }

  AndroidWidgetStyle get androidStyle {
    return AndroidWidgetStyle.fromId(id);
  }

  String get launcherRequestLabel => previewCellLabel.replaceAll('x', '×');

  String get label => WidgetUiCopy.displayModeLabel(id);
  String get description => WidgetUiCopy.displayModeDescription(id);

  double aspectRatio({bool isAndroid = false}) {
    if (this == WidgetDisplayMode.standard && isAndroid) {
      return 18 / 11;
    }
    return previewAspectRatio;
  }
}

class _WidgetDisplayModePanel extends StatelessWidget {
  final WidgetHostPlatform hostPlatform;
  final WidgetDisplayMode value;
  final bool enabled;
  final bool loading;
  final bool loadFailed;
  final VoidCallback onReload;
  final bool syncPending;
  final bool syncing;
  final VoidCallback? onRetrySync;
  final ValueChanged<WidgetDisplayMode>? onChanged;

  const _WidgetDisplayModePanel({
    required this.hostPlatform,
    required this.value,
    this.enabled = true,
    required this.loading,
    required this.loadFailed,
    required this.onReload,
    required this.syncPending,
    required this.syncing,
    required this.onRetrySync,
    required this.onChanged,
  });

  String _label(WidgetDisplayMode mode) =>
      hostPlatform == WidgetHostPlatform.android
      ? '${mode.label} ${mode.launcherRequestLabel}'
      : mode.label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final surfaceStyle = appSurfaceStyleOf(context);
    final isPriorityTheme = surfaceStyle != null;
    final cardFill = surfaceStyle?.cardFillColor ?? cs.surface;
    final cardBackground = Color.alphaBlend(
      cardFill,
      theme.scaffoldBackgroundColor,
    );
    final retryButtonStyle = isPriorityTheme
        ? TextButton.styleFrom(
            foregroundColor: appReadableForeground(
              cardBackground,
              cs.onSurface,
            ),
          )
        : null;
    final errorColor = isPriorityTheme
        ? appReadableForeground(cardBackground, cs.error)
        : cs.error;
    return AppSurfaceCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  WidgetUiCopy.stylePanelTitle,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.normal,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final direction = _widgetSegmentDirection(
                context,
                constraints,
                WidgetDisplayMode.values.map(_label),
              );
              const segmentPadding = EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 4,
              );
              final segmentMinWidth =
                  direction == Axis.vertical &&
                      constraints.maxWidth > segmentPadding.horizontal
                  ? constraints.maxWidth - segmentPadding.horizontal
                  : 0.0;
              final segmented = SegmentedButton<WidgetDisplayMode>(
                direction: direction,
                style: ButtonStyle(
                  textStyle: WidgetStatePropertyAll(
                    appSecondaryControlTextStyle(context),
                  ),
                  visualDensity: VisualDensity(vertical: 1),
                  shape: WidgetStatePropertyAll<OutlinedBorder>(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(
                        Radius.circular(
                          appSurfaceStyleOf(context)?.smallTileRadius ?? 10,
                        ),
                      ),
                    ),
                  ),
                  padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
                    segmentPadding,
                  ),
                  tapTargetSize: MaterialTapTargetSize.padded,
                ),
                segments: [
                  for (final mode in WidgetDisplayMode.values)
                    ButtonSegment(
                      value: mode,
                      label: ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth: segmentMinWidth,
                          minHeight: 44,
                        ),
                        child: Center(
                          child: Text(
                            _label(mode),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                ],
                selected: {value},
                showSelectedIcon: false,
                onSelectionChanged: enabled && onChanged != null
                    ? (next) => onChanged!(next.single)
                    : null,
              );
              return SizedBox(width: double.infinity, child: segmented);
            },
          ),
          const SizedBox(height: 8),
          Text(
            WidgetUiCopy.hostStyleDescription(value.id, hostPlatform),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.normal,
              color: cs.onSurfaceVariant,
            ),
          ),
          if (syncPending && !loading && !loadFailed) ...[
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(
                syncing
                    ? WidgetUiCopy.updatingStyle
                    : WidgetUiCopy.styleSyncPending,
                key: const ValueKey('widget_style_sync_pending'),
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                key: const ValueKey('widget_style_sync_retry'),
                onPressed: syncing ? null : onRetrySync,
                style: retryButtonStyle,
                icon: const Icon(Icons.refresh, size: 16),
                label: Text(WidgetUiCopy.actionRetry),
              ),
            ),
          ],
          if (loading || loadFailed) ...[
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(
                loading
                    ? WidgetUiCopy.loadingStyle
                    : WidgetUiCopy.styleLoadFailed,
                style: TextStyle(
                  fontSize: 12,
                  color: loadFailed ? errorColor : cs.onSurfaceVariant,
                ),
              ),
            ),
            if (loadFailed)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  key: const ValueKey('widget_style_load_retry'),
                  onPressed: onReload,
                  style: retryButtonStyle,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text(WidgetUiCopy.actionRetry),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Keeps widget operations and feedback attached to their original session.
class _WidgetActionOrigin {
  _WidgetActionOrigin._({
    required this.auth,
    required this.lock,
    required this.update,
    required this.route,
    required this.sessionLease,
    required this.leaseFailed,
    required this.isCallerAvailable,
  }) : accountGeneration = AccountLocalDataCleaner.accountDataGeneration,
       sessionGeneration = auth?.sessionGeneration,
       wasLoggedIn = auth?.state.isLoggedIn ?? false,
       _userId = _normalize(auth?.state.userId);

  final AuthProvider? auth;
  final AppLockProvider? lock;
  final AppUpdateService? update;
  final ModalRoute<dynamic>? route;
  final AuthSessionLease? sessionLease;
  final bool leaseFailed;
  final bool Function() isCallerAvailable;
  final int accountGeneration;
  final int? sessionGeneration;
  final bool wasLoggedIn;
  String? _userId;

  static String? _normalize(String? raw) {
    final value = raw?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  static _WidgetActionOrigin capture(
    BuildContext context, {
    required bool Function() isCallerAvailable,
  }) {
    final auth = context.read<AuthProvider?>();
    AuthSessionLease? lease;
    var failed = false;
    if (auth?.state.isLoggedIn == true) {
      try {
        lease = auth!.captureSessionLease();
      } catch (_) {
        failed = true;
      }
    }
    return _WidgetActionOrigin._(
      auth: auth,
      lock: context.read<AppLockProvider?>(),
      update: context.read<AppUpdateService?>(),
      route: ModalRoute.of(context),
      sessionLease: lease,
      leaseFailed: failed,
      isCallerAvailable: isCallerAvailable,
    );
  }

  bool isCurrent(BuildContext context, {bool checkRoute = true}) {
    if (!isAccountCurrent(context)) return false;
    if (!isCallerAvailable() ||
        (route != null &&
            (!route!.isActive || (checkRoute && !route!.isCurrent))) ||
        lock?.isLocked == true ||
        update?.mustUpdate == true) {
      return false;
    }
    return true;
  }

  bool isAccountCurrent(BuildContext context) {
    if (!context.mounted ||
        leaseFailed ||
        !AccountLocalDataCleaner.isCurrentAccountDataGeneration(
          accountGeneration,
        )) {
      return false;
    }
    try {
      if (!identical(context.read<AuthProvider?>(), auth) ||
          !identical(context.read<AppLockProvider?>(), lock) ||
          !identical(context.read<AppUpdateService?>(), update)) {
        return false;
      }
      final currentAuth = auth;
      if (currentAuth != null) {
        if (currentAuth.sessionGeneration != sessionGeneration ||
            currentAuth.state.isLoggedIn != wasLoggedIn ||
            currentAuth.isAccountTransitionInProgress ||
            currentAuth.isLocalAccountDataBlocked ||
            (sessionLease != null &&
                !currentAuth.isSessionLeaseCurrent(sessionLease!))) {
          return false;
        }
        final id = _normalize(currentAuth.state.userId);
        if (_userId != null && id != _userId) return false;
        _userId ??= id;
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}

class _AddWidgetButton extends StatefulWidget {
  final WidgetHostPlatform hostPlatform;
  final bool isActive;
  final int hostGeneration;
  final ValueGetter<int> activityGeneration;
  final bool requesting;
  final bool Function() beginRequest;
  final VoidCallback endRequest;
  final DuoyiWidgetKind kind;
  final WidgetDisplayMode displayMode;
  final String? styleStatusLabel;
  final int styleRevision;
  final ValueGetter<int> currentStyleRevision;
  final AndroidWidgetPinResult? pinSupport;
  final bool checkingPinSupport;
  final bool canOpenWidgetSettings;
  final ValueChanged<AndroidWidgetPinResult> onPinSupportChanged;

  const _AddWidgetButton({
    required this.hostPlatform,
    required this.isActive,
    required this.hostGeneration,
    required this.activityGeneration,
    required this.requesting,
    required this.beginRequest,
    required this.endRequest,
    super.key,
    required this.kind,
    required this.displayMode,
    required this.styleStatusLabel,
    required this.styleRevision,
    required this.currentStyleRevision,
    required this.pinSupport,
    required this.checkingPinSupport,
    required this.canOpenWidgetSettings,
    required this.onPinSupportChanged,
  });

  @override
  State<_AddWidgetButton> createState() => _AddWidgetButtonState();
}

class _AddWidgetButtonState extends State<_AddWidgetButton> {
  bool _showingHelp = false;

  @override
  Widget build(BuildContext context) {
    final host = widget.hostPlatform;
    final hostGeneration = widget.hostGeneration;
    final activityGeneration = widget.activityGeneration();
    final wasActive = widget.isActive;
    final origin = _WidgetActionOrigin.capture(
      context,
      isCallerAvailable: () =>
          mounted &&
          wasActive &&
          widget.isActive &&
          widget.activityGeneration() == activityGeneration &&
          widget.hostPlatform == host &&
          widget.hostGeneration == hostGeneration,
    );
    final support = widget.pinSupport;
    final manualHost = widget.hostPlatform != WidgetHostPlatform.android;
    final disabledByPlatform =
        !widget.checkingPinSupport &&
        support != null &&
        support != AndroidWidgetPinResult.requested;
    final label = manualHost
        ? WidgetUiCopy.hostAddAction(widget.hostPlatform)
        : widget.styleStatusLabel != null
        ? widget.styleStatusLabel!
        : widget.checkingPinSupport
        ? WidgetUiCopy.checkingDesktopSupport
        : disabledByPlatform
        ? WidgetUiCopy.pinDisabledAction(support)
        : widget.requesting
        ? WidgetUiCopy.requestingAdd
        : WidgetUiCopy.addWidgetButtonLabel(
            modeLabel: widget.displayMode.label,
            launcherRequestLabel: widget.displayMode.launcherRequestLabel,
          );
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 280.0;
        return Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: maxWidth,
            child: FilledButton.icon(
              onPressed: manualHost
                  ? () => _showPinWidgetHelp(
                      context,
                      AndroidWidgetPinResult.unsupportedPlatform,
                      origin,
                    )
                  : widget.styleStatusLabel != null ||
                        widget.requesting ||
                        widget.checkingPinSupport
                  ? null
                  : disabledByPlatform
                  ? () => _showPinWidgetHelp(context, support, origin)
                  : () => _request(context, origin),
              style: appSecondaryFilledButtonStyle(context).copyWith(
                minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
                visualDensity: VisualDensity.standard,
              ),
              icon: widget.requesting && !_showingHelp && !manualHost
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      manualHost || disabledByPlatform
                          ? Icons.help_outline
                          : widget.styleStatusLabel != null
                          ? Icons.hourglass_empty
                          : Icons.add_to_home_screen_outlined,
                    ),
              label: Semantics(
                label: '${WidgetUiCopy.catalogTitle(widget.kind)} $label',
                excludeSemantics: true,
                child: Text(label, textAlign: TextAlign.center),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _request(
    BuildContext context,
    _WidgetActionOrigin origin,
  ) async {
    if (widget.hostPlatform != WidgetHostPlatform.android ||
        !origin.isCurrent(context) ||
        widget.currentStyleRevision() != widget.styleRevision ||
        !widget.beginRequest()) {
      return;
    }
    final requestedKind = widget.kind;
    final requestedMode = widget.displayMode;
    final requestedStyleRevision = widget.styleRevision;
    // Keep the page-owned lease even if filtering disposes this button.
    final endRequest = widget.endRequest;
    try {
      final support = await AndroidWidgetManager.checkPinSupport();
      if (!context.mounted ||
          !origin.isCurrent(context) ||
          widget.currentStyleRevision() != requestedStyleRevision) {
        return;
      }
      // A style selection can finish (or return to the same value) while the
      // launcher support query is pending. Only hand off the original choice
      // when no intervening style operation has occurred.
      widget.onPinSupportChanged(support);
      if (support != AndroidWidgetPinResult.requested) {
        await AndroidWidgetManager.refreshAllWidgets();
        if (!context.mounted || !origin.isCurrent(context)) return;
        await _showPinWidgetHelp(context, support, origin);
        return;
      }
      final request = await AndroidWidgetManager.requestPinWidgetDetailed(
        requestedKind,
        style: requestedMode.androidStyle,
      );
      if (request.result == AndroidWidgetPinResult.requested) {
        if (context.mounted && origin.isCurrent(context)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: _widgetFeedback(
                () => WidgetUiCopy.pinInitiatedSnackBar(requestedMode.label),
              ),
            ),
          );
        }
        final requestId = request.requestId;
        if (requestId == null || requestId.isEmpty) return;
        final confirmation = await AndroidWidgetManager.waitForPinResult(
          requestId,
        );
        if (!context.mounted || !origin.isCurrent(context)) return;
        if (confirmation.isSuccess) {
          await AndroidWidgetManager.refreshAllWidgets();
          if (!context.mounted || !origin.isCurrent(context)) return;
          ScaffoldMessenger.of(context).removeCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: _widgetFeedback(
                () => WidgetUiCopy.pinSuccessSnackBar(requestedMode.label),
              ),
            ),
          );
          return;
        }
        await AndroidWidgetManager.refreshAllWidgets();
        if (!context.mounted || !origin.isCurrent(context)) return;
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
        await _showPinWidgetConfirmationFailureHelp(
          context,
          confirmation,
          origin,
        );
        return;
      }
      if (!context.mounted || !origin.isCurrent(context)) return;
      await AndroidWidgetManager.refreshAllWidgets();
      if (!context.mounted || !origin.isCurrent(context)) return;
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      await _showPinWidgetHelp(context, request.result, origin);
    } finally {
      endRequest();
    }
  }

  Future<void> _showPinWidgetHelp(
    BuildContext context,
    AndroidWidgetPinResult result,
    _WidgetActionOrigin origin,
  ) async {
    final host = widget.hostPlatform;
    await _showHelp(
      context,
      origin,
      title: () => host == WidgetHostPlatform.android
          ? WidgetUiCopy.addDialogTitle
          : WidgetUiCopy.hostHelpTitle(host),
      message: () => host == WidgetHostPlatform.android
          ? WidgetUiCopy.pinHelpMessage(result)
          : WidgetUiCopy.hostHelpMessage(host),
    );
  }

  Future<void> _showPinWidgetConfirmationFailureHelp(
    BuildContext context,
    AndroidWidgetPinConfirmation confirmation,
    _WidgetActionOrigin origin,
  ) async {
    await _showHelp(
      context,
      origin,
      title: () => WidgetUiCopy.pinConfirmationFailure(confirmation.status).$1,
      message: () =>
          WidgetUiCopy.pinConfirmationFailure(confirmation.status).$2,
    );
  }

  Future<void> _showHelp(
    BuildContext context,
    _WidgetActionOrigin origin, {
    required ValueGetter<String> title,
    required ValueGetter<String> message,
  }) async {
    if (!context.mounted || !origin.isCurrent(context)) return;
    final canOpenSettings =
        widget.hostPlatform == WidgetHostPlatform.android &&
        widget.canOpenWidgetSettings;
    setState(() => _showingHelp = true);
    try {
      await showControllerDialog<void>(
        context: context,
        controllers: const [],
        builder: (dialogContext) {
          final dialogRoute = ModalRoute.of(dialogContext);
          bool canDismiss() =>
              dialogContext.mounted &&
              dialogRoute?.isActive == true &&
              dialogRoute?.isCurrent == true;
          bool canAct() =>
              canDismiss() && origin.isCurrent(context, checkRoute: false);
          return ValueListenableBuilder<AppLocale>(
            valueListenable: I18n.localeListenable,
            builder: (ctx, _, _) => AppDialog(
              title: Text(title()),
              content: Text(message()),
              actions: [
                if (canOpenSettings)
                  TextButton.icon(
                    onPressed: () async {
                      if (!canAct()) return;
                      Navigator.of(dialogContext).pop();
                      await _openWidgetSettings(context, origin);
                    },
                    icon: const Icon(Icons.settings_outlined),
                    label: Text(WidgetUiCopy.actionOpenPermissions),
                  ),
                FilledButton(
                  onPressed: () {
                    if (canDismiss()) Navigator.of(dialogContext).pop();
                  },
                  style: appSecondaryFilledButtonStyle(ctx),
                  child: Text(WidgetUiCopy.actionGotIt),
                ),
              ],
            ),
          );
        },
      );
    } finally {
      if (mounted) setState(() => _showingHelp = false);
    }
  }

  Future<void> _openWidgetSettings(
    BuildContext context,
    _WidgetActionOrigin origin,
  ) async {
    if (widget.hostPlatform != WidgetHostPlatform.android ||
        !origin.isCurrent(context)) {
      return;
    }
    final opened = await AndroidWidgetManager.openWidgetSettings();
    if (!context.mounted || !origin.isCurrent(context)) return;
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: _widgetFeedback(() => WidgetUiCopy.cannotOpenSettings),
        ),
      );
    }
  }
}

T? _watchOptionalProvider<T extends Object>(BuildContext context) {
  try {
    return Provider.of<T>(context, listen: true);
  } on ProviderNotFoundException {
    return null;
  }
}

class _WidgetPreviewScope extends InheritedWidget {
  final bool? darkOverride;
  final bool useRealData;

  const _WidgetPreviewScope({
    required this.darkOverride,
    required this.useRealData,
    required super.child,
  });

  static _WidgetPreviewScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_WidgetPreviewScope>();

  @override
  bool updateShouldNotify(_WidgetPreviewScope oldWidget) =>
      oldWidget.darkOverride != darkOverride ||
      oldWidget.useRealData != useRealData;
}

class _WidgetPreviewDataScope extends InheritedWidget {
  final bool useRealData;

  const _WidgetPreviewDataScope({
    required this.useRealData,
    required super.child,
  });

  static bool isRealData(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_WidgetPreviewDataScope>()
          ?.useRealData ??
      false;

  @override
  bool updateShouldNotify(_WidgetPreviewDataScope oldWidget) =>
      oldWidget.useRealData != useRealData;
}

class WidgetPreviewCard extends StatelessWidget {
  final WidgetPreviewKind kind;
  final WidgetDisplayMode displayMode;
  final TargetPlatform? platformOverride;
  final bool? darkOverride;
  final bool? useRealData;

  const WidgetPreviewCard.todo({
    super.key,
    this.displayMode = WidgetDisplayMode.standard,
    this.platformOverride,
    this.darkOverride,
    this.useRealData,
  }) : kind = WidgetPreviewKind.todo;
  const WidgetPreviewCard.focus({
    super.key,
    this.displayMode = WidgetDisplayMode.standard,
    this.platformOverride,
    this.darkOverride,
    this.useRealData,
  }) : kind = WidgetPreviewKind.focus;
  const WidgetPreviewCard.habit({
    super.key,
    this.displayMode = WidgetDisplayMode.standard,
    this.platformOverride,
    this.darkOverride,
    this.useRealData,
  }) : kind = WidgetPreviewKind.habit;
  const WidgetPreviewCard.calendar({
    super.key,
    this.displayMode = WidgetDisplayMode.standard,
    this.platformOverride,
    this.darkOverride,
    this.useRealData,
  }) : kind = WidgetPreviewKind.calendar;
  const WidgetPreviewCard.schedule({
    super.key,
    this.displayMode = WidgetDisplayMode.standard,
    this.platformOverride,
    this.darkOverride,
    this.useRealData,
  }) : kind = WidgetPreviewKind.schedule;
  const WidgetPreviewCard.goal({
    super.key,
    this.displayMode = WidgetDisplayMode.standard,
    this.platformOverride,
    this.darkOverride,
    this.useRealData,
  }) : kind = WidgetPreviewKind.goal;
  const WidgetPreviewCard.course({
    super.key,
    this.displayMode = WidgetDisplayMode.standard,
    this.platformOverride,
    this.darkOverride,
    this.useRealData,
  }) : kind = WidgetPreviewKind.course;
  const WidgetPreviewCard.note({
    super.key,
    this.displayMode = WidgetDisplayMode.standard,
    this.platformOverride,
    this.darkOverride,
    this.useRealData,
  }) : kind = WidgetPreviewKind.note;
  const WidgetPreviewCard.anniversary({
    super.key,
    this.displayMode = WidgetDisplayMode.standard,
    this.platformOverride,
    this.darkOverride,
    this.useRealData,
  }) : kind = WidgetPreviewKind.anniversary;
  const WidgetPreviewCard.diary({
    super.key,
    this.displayMode = WidgetDisplayMode.standard,
    this.platformOverride,
    this.darkOverride,
    this.useRealData,
  }) : kind = WidgetPreviewKind.diary;

  bool _resolveIsAndroid(BuildContext context) {
    if (platformOverride != null) {
      return platformOverride == TargetPlatform.android;
    }
    return PlatformInfo.isAndroid;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, _, _) {
        return _buildCard(context);
      },
    );
  }

  Widget _buildCard(BuildContext context) {
    final previewScope = _WidgetPreviewScope.maybeOf(context);
    final effectiveDarkOverride = darkOverride ?? previewScope?.darkOverride;
    final effectiveUseRealData =
        useRealData ?? previewScope?.useRealData ?? false;
    ThemeProvider? themeProvider;
    ThemeProvider? fallbackProvider;
    try {
      themeProvider = context.watch<ThemeProvider>();
    } on ProviderNotFoundException {
      fallbackProvider = ThemeProvider();
      themeProvider = fallbackProvider;
    }
    final provider = themeProvider;
    final widgetBrand = provider.activeWidgetBackgroundBrand;
    final widgetTheme = effectiveDarkOverride == null
        ? HomeWidgetThemePayload.fromThemeProvider(provider)
        : HomeWidgetThemePayload.fromThemeProvider(
            provider,
            darkOverride: effectiveDarkOverride,
          );
    // Preview fixtures can render outside the app Provider tree. Release the
    // temporary ChangeNotifier immediately after extracting immutable values.
    fallbackProvider?.dispose();
    final baseTheme = widgetBrand.theme;
    final previewBrightness = widgetTheme.dark
        ? Brightness.dark
        : Brightness.light;
    final cs = baseTheme.colorScheme.copyWith(
      brightness: previewBrightness,
      primary: widgetTheme.primary,
      onPrimary: widgetTheme.onPrimary,
      secondary: widgetTheme.accentEnd,
      surface: widgetTheme.surface,
      onSurface: widgetTheme.text,
      onSurfaceVariant: widgetTheme.mutedText,
      outlineVariant: widgetTheme.border,
    );
    final accent = widgetTheme.primary;
    final title = WidgetUiCopy.previewTitle(kind);
    final headerTitle = effectiveUseRealData
        ? title
        : WidgetUiCopy.previewSampleBadge(title);
    final previewBackgroundAsset = widgetBrand.backgroundAsset;
    final imageBacked = previewBackgroundAsset != null;
    final previewBackground = widgetTheme.background;
    final imageOverlay = widgetTheme.dark
        ? const Color.fromARGB(92, 0, 0, 0)
        : const Color.fromARGB(78, 255, 255, 255);
    final previewCardRadius = widgetTheme.cornerRadiusDp.toDouble();
    final appBodyStyle = Theme.of(context).textTheme.bodyMedium;
    final previewTheme = baseTheme.copyWith(
      brightness: previewBrightness,
      colorScheme: cs,
      textTheme: baseTheme.textTheme.apply(
        fontFamily: appBodyStyle?.fontFamily,
        fontFamilyFallback: appBodyStyle?.fontFamilyFallback,
        bodyColor: widgetTheme.text,
        displayColor: widgetTheme.text,
      ),
    );
    final isAndroidPlatform = _resolveIsAndroid(context);
    final baseAspectRatio = displayMode.aspectRatio(
      isAndroid: isAndroidPlatform,
    );
    final showFooter = isAndroidPlatform
        ? displayMode == WidgetDisplayMode.detailed
        : displayMode != WidgetDisplayMode.compact;
    final navigation = showFooter
        ? _WidgetPreviewNav(
            selectedIndex: switch (kind) {
              WidgetPreviewKind.todo => 0,
              WidgetPreviewKind.focus => 3,
              WidgetPreviewKind.habit => 1,
              _ => 2,
            },
            accent: accent,
          )
        : null;
    return _WidgetPreviewDataScope(
      useRealData: effectiveUseRealData,
      child: Theme(
        data: previewTheme,
        child: DefaultTextStyle.merge(
          style: previewTheme.textTheme.bodyMedium,
          child: Builder(
            builder: (context) {
              return Semantics(
                label:
                    '$title ${isAndroidPlatform ? displayMode.previewCellLabel : displayMode.label}',
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final available = constraints.maxWidth.isFinite
                        ? constraints.maxWidth
                        : displayMode.previewMaxWidth;
                    final width = available < displayMode.previewMaxWidth
                        ? available
                        : displayMode.previewMaxWidth;
                    final titleHeight = _widgetPreviewTextSize(
                      context,
                      headerTitle,
                      12,
                      width: (width - 24 - widgetTheme.borderWidthDp * 2 - 22)
                          .clamp(0.0, double.infinity),
                      maxLines: null,
                    ).height;
                    final refreshSize = _widgetPreviewTextSize(
                      context,
                      '↻',
                      11,
                    );
                    final refreshHeight = refreshSize.height;
                    final refreshWidth = refreshSize.width;
                    final bodyWidth =
                        width - 24 - widgetTheme.borderWidthDp * 2;
                    final dateWidth = (bodyWidth - refreshWidth).clamp(
                      0.0,
                      double.infinity,
                    );
                    final cellTag = isAndroidPlatform
                        ? displayMode.previewCellLabel
                        : displayMode.label;
                    final now = DateTime.now();
                    final dateLabel = effectiveUseRealData
                        ? '${now.month}/${now.day} · $cellTag'
                        : WidgetUiCopy.sampleHeaderDate(cellTag);
                    final dateHeight = _widgetPreviewTextSize(
                      context,
                      dateLabel,
                      10,
                      width: dateWidth,
                      maxLines: null,
                    ).height;
                    final baseTitleHeight = _widgetPreviewTextSize(
                      context,
                      headerTitle,
                      12,
                    ).height;
                    final baseDateHeight = _widgetPreviewTextSize(
                      context,
                      dateLabel,
                      10,
                    ).height;
                    final baseHeaderHeight =
                        (baseTitleHeight > 16 ? baseTitleHeight : 16) +
                        3 +
                        (baseDateHeight > refreshHeight
                            ? baseDateHeight
                            : refreshHeight) +
                        10 +
                        24;
                    final headerHeight =
                        (titleHeight > 16 ? titleHeight : 16) +
                        3 +
                        (dateHeight > refreshHeight
                            ? dateHeight
                            : refreshHeight) +
                        10 +
                        24;
                    final extraHeaderHeight = headerHeight > baseHeaderHeight
                        ? headerHeight - baseHeaderHeight
                        : 0.0;
                    final focusMetrics = kind == WidgetPreviewKind.focus
                        ? _WidgetPreviewFocusBody.metricsFor(
                            context,
                            displayMode == WidgetDisplayMode.compact ? 1 : 2,
                            bodyWidth,
                          )
                        : const <_WidgetPreviewMetric>[];
                    final primaryHeight = switch (kind) {
                      WidgetPreviewKind.todo => _WidgetPreviewTodoRow(
                        text: WidgetUiCopy.todoItem1,
                      ).heightFor(context, bodyWidth),
                      WidgetPreviewKind.focus =>
                        focusMetrics
                            .map(
                              (metric) => metric.heightFor(
                                context,
                                bodyWidth / focusMetrics.length,
                              ),
                            )
                            .reduce((a, b) => a > b ? a : b),
                      WidgetPreviewKind.habit => _WidgetPreviewQuickAdd(
                        label: WidgetUiCopy.habitCheckInButton,
                      ).heightFor(context, bodyWidth),
                      WidgetPreviewKind.calendar => _widgetPreviewTextSize(
                        context,
                        WidgetUiCopy.calendarCurrentDay,
                        11,
                        width: bodyWidth,
                        maxLines: null,
                      ).height,
                      WidgetPreviewKind.schedule => _WidgetPreviewLine(
                        icon: Icons.notifications_active_outlined,
                        text: WidgetUiCopy.scheduleItem1,
                      ).heightFor(context, bodyWidth),
                      WidgetPreviewKind.goal => _WidgetPreviewLine(
                        icon: Icons.flag_outlined,
                        text: WidgetUiCopy.goalItem1,
                      ).heightFor(context, bodyWidth),
                      WidgetPreviewKind.course => _WidgetPreviewLine(
                        icon: Icons.school_outlined,
                        text: WidgetUiCopy.courseItem1,
                      ).heightFor(context, bodyWidth),
                      WidgetPreviewKind.note => _WidgetPreviewLine(
                        icon: Icons.edit_note_outlined,
                        text: WidgetUiCopy.noteItem1,
                      ).heightFor(context, bodyWidth),
                      WidgetPreviewKind.anniversary => _WidgetPreviewLine(
                        icon: Icons.event_available_outlined,
                        text: WidgetUiCopy.anniversaryItem1,
                      ).heightFor(context, bodyWidth),
                      WidgetPreviewKind.diary => _WidgetPreviewLine(
                        icon: Icons.book_outlined,
                        text: WidgetUiCopy.diaryItem1,
                      ).heightFor(context, bodyWidth),
                    };
                    final aspectHeight =
                        width /
                        baseAspectRatio *
                        (MediaQuery.textScalerOf(context).scale(12) / 12).clamp(
                          1.0,
                          2.0,
                        );
                    final baseMinimumHeight =
                        baseHeaderHeight +
                        primaryHeight +
                        widgetTheme.borderWidthDp * 2 +
                        1;
                    final baseCardHeight = aspectHeight > baseMinimumHeight
                        ? aspectHeight
                        : baseMinimumHeight;
                    final cardHeight = baseCardHeight + extraHeaderHeight;
                    final surfaceCard = Container(
                      key: const ValueKey('widget_preview_surface'),
                      clipBehavior: Clip.hardEdge,
                      decoration: BoxDecoration(
                        color: imageBacked ? cs.surface : previewBackground,
                        borderRadius: BorderRadius.circular(previewCardRadius),
                        border: widgetTheme.borderWidthDp == 0
                            ? null
                            : Border.all(
                                color: widgetTheme.border,
                                width: widgetTheme.borderWidthDp.toDouble(),
                              ),
                      ),
                      child: _WidgetPreviewTheme(
                        payload: widgetTheme,
                        child: Stack(
                          children: [
                            if (imageBacked)
                              Positioned.fill(
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    final dpr = MediaQuery.devicePixelRatioOf(
                                      context,
                                    ).clamp(1.0, 3.0);
                                    final cacheWidth =
                                        (constraints.maxWidth * dpr)
                                            .ceil()
                                            .clamp(1, 1600);
                                    final cacheHeight =
                                        (constraints.maxHeight * dpr)
                                            .ceil()
                                            .clamp(1, 1600);
                                    return Image.asset(
                                      previewBackgroundAsset,
                                      fit: BoxFit.cover,
                                      alignment: Alignment.center,
                                      cacheWidth: cacheWidth,
                                      cacheHeight: cacheHeight,
                                      filterQuality: FilterQuality.low,
                                      gaplessPlayback: true,
                                      errorBuilder: (context, error, stack) =>
                                          DecoratedBox(
                                            decoration: BoxDecoration(
                                              color: previewBackground,
                                            ),
                                          ),
                                    );
                                  },
                                ),
                              ),
                            if (imageBacked)
                              Positioned.fill(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: imageOverlay,
                                  ),
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        switch (kind) {
                                          WidgetPreviewKind.todo =>
                                            Icons.checklist_rtl_outlined,
                                          WidgetPreviewKind.focus =>
                                            Icons.timer_outlined,
                                          WidgetPreviewKind.habit =>
                                            Icons.self_improvement_outlined,
                                          WidgetPreviewKind.calendar =>
                                            Icons.calendar_month_outlined,
                                          WidgetPreviewKind.schedule =>
                                            Icons.event_note_outlined,
                                          WidgetPreviewKind.goal =>
                                            Icons.flag_outlined,
                                          WidgetPreviewKind.course =>
                                            Icons.school_outlined,
                                          WidgetPreviewKind.note =>
                                            Icons.edit_note_outlined,
                                          WidgetPreviewKind.anniversary =>
                                            Icons.event_available_outlined,
                                          WidgetPreviewKind.diary =>
                                            Icons.book_outlined,
                                        },
                                        size: 16,
                                        color: accent,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          headerTitle,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.normal,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          dateLabel,
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: cs.onSurfaceVariant,
                                            fontWeight: FontWeight.normal,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        '↻',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: cs.onSurfaceVariant,
                                          fontWeight: FontWeight.normal,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Expanded(
                                    child: _WidgetPreviewContentFrame(
                                      mode: displayMode,
                                      navigation: navigation,
                                      child: switch (kind) {
                                        WidgetPreviewKind.todo =>
                                          _WidgetPreviewTodoBody(),
                                        WidgetPreviewKind.focus =>
                                          _WidgetPreviewFocusBody(),
                                        WidgetPreviewKind.habit =>
                                          _WidgetPreviewHabitBody(),
                                        WidgetPreviewKind.calendar =>
                                          _WidgetPreviewCalendarBody(),
                                        WidgetPreviewKind.schedule =>
                                          _WidgetPreviewScheduleBody(),
                                        WidgetPreviewKind.goal =>
                                          _WidgetPreviewGoalBody(),
                                        WidgetPreviewKind.course =>
                                          _WidgetPreviewCourseBody(),
                                        WidgetPreviewKind.note =>
                                          _WidgetPreviewNoteBody(),
                                        WidgetPreviewKind.anniversary =>
                                          _WidgetPreviewAnniversaryBody(),
                                        WidgetPreviewKind.diary =>
                                          _WidgetPreviewDiaryBody(),
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                    final needsDarkBackdrop =
                        widgetTheme.dark &&
                        !imageBacked &&
                        previewBackground.a < 1.0;
                    return Align(
                      alignment: Alignment.center,
                      child: SizedBox(
                        width: width,
                        child: SizedBox(
                          height: cardHeight,
                          child: needsDarkBackdrop
                              ? DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0B0F17),
                                    borderRadius: BorderRadius.circular(
                                      previewCardRadius,
                                    ),
                                  ),
                                  child: surfaceCard,
                                )
                              : surfaceCard,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _WidgetPreviewTheme extends InheritedWidget {
  final HomeWidgetThemePayload payload;

  const _WidgetPreviewTheme({required this.payload, required super.child});

  static HomeWidgetThemePayload of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_WidgetPreviewTheme>()!
      .payload;

  static HomeWidgetThemePayload? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_WidgetPreviewTheme>()
      ?.payload;

  @override
  bool updateShouldNotify(_WidgetPreviewTheme oldWidget) =>
      payload.signature != oldWidget.payload.signature;
}

bool _isOpaquePreviewMetricCandidate(HomeWidgetThemePayload payload) {
  final isSupportedBrand =
      payload.brandId == 'defaultBrand' || payload.brandId == 'liquidGlass';
  final isPlainCard = payload.cardSkinId == ThemeProvider.defaultCardSkinId;
  final hasNoPhoto = payload.backgroundAssetKey.isEmpty;
  final isOpaqueBackground = payload.background.a == 1.0;
  return isSupportedBrand && isPlainCard && hasNoPhoto && isOpaqueBackground;
}

class _WidgetPreviewDensity extends StatelessWidget {
  final WidgetDisplayMode mode;
  final Widget child;

  const _WidgetPreviewDensity({required this.mode, required this.child});

  @override
  Widget build(BuildContext context) {
    final maxLines = switch (mode) {
      WidgetDisplayMode.compact => 1,
      WidgetDisplayMode.standard => 2,
      WidgetDisplayMode.detailed => 3,
    };
    return _WidgetPreviewDensityScope(maxLines: maxLines, child: child);
  }
}

class _WidgetPreviewContentFrame extends StatelessWidget {
  final WidgetDisplayMode mode;
  final Widget child;
  final _WidgetPreviewNav? navigation;

  const _WidgetPreviewContentFrame({
    required this.mode,
    required this.child,
    this.navigation,
  });

  @override
  Widget build(BuildContext context) => _WidgetPreviewDensity(
    mode: mode,
    child: _WidgetPreviewListScope(navigation: navigation, child: child),
  );
}

class _WidgetPreviewListScope extends InheritedWidget {
  final _WidgetPreviewNav? navigation;

  const _WidgetPreviewListScope({
    required this.navigation,
    required super.child,
  });

  static _WidgetPreviewNav? navigationOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_WidgetPreviewListScope>()
      ?.navigation;

  @override
  bool updateShouldNotify(_WidgetPreviewListScope oldWidget) =>
      oldWidget.navigation != navigation;
}

class _WidgetPreviewDensityScope extends InheritedWidget {
  final int maxLines;

  const _WidgetPreviewDensityScope({
    required this.maxLines,
    required super.child,
  });

  static int maxLinesOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<_WidgetPreviewDensityScope>()
            ?.maxLines ??
        2;
  }

  @override
  bool updateShouldNotify(_WidgetPreviewDensityScope oldWidget) {
    return maxLines != oldWidget.maxLines;
  }
}

Size _widgetPreviewTextSize(
  BuildContext context,
  String text,
  double fontSize, {
  double width = double.infinity,
  int? maxLines = 1,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: _widgetMeasurementStyle(
        context,
        TextStyle(fontSize: fontSize, fontWeight: FontWeight.normal),
      ),
    ),
    maxLines: maxLines,
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    locale: Localizations.maybeLocaleOf(context),
    textHeightBehavior:
        DefaultTextStyle.of(context).textHeightBehavior ??
        DefaultTextHeightBehavior.maybeOf(context),
  )..layout(maxWidth: width.clamp(0.0, double.infinity));
  final size = painter.size;
  painter.dispose();
  return size;
}

class _WidgetPreviewPart {
  final Widget child;
  final double height;
  final double gap;
  final int priority;
  final bool optional;

  const _WidgetPreviewPart({
    required this.child,
    required this.height,
    this.gap = 0,
    this.priority = 0,
    this.optional = false,
  });

  double get extent => height + gap;
}

/// Select by content priority, then preserve visual order. Navigation is last.
class _WidgetPreviewParts extends StatelessWidget {
  final List<_WidgetPreviewPart> parts;

  const _WidgetPreviewParts({required this.parts});

  @override
  Widget build(BuildContext context) {
    final navigation = _WidgetPreviewListScope.navigationOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final requiredOrder = [
          for (var i = 0; i < parts.length; i++)
            if (!parts[i].optional) i,
        ]..sort((a, b) {
            final priority = parts[a].priority.compareTo(parts[b].priority);
            return priority == 0 ? a.compareTo(b) : priority;
          });
        final optionalOrder = [
          for (var i = 0; i < parts.length; i++)
            if (parts[i].optional) i,
        ]..sort((a, b) {
            final priority = parts[a].priority.compareTo(parts[b].priority);
            return priority == 0 ? a.compareTo(b) : priority;
          });
        final selected = <int>{};
        var usedHeight = 0.0;
        for (final index in requiredOrder) {
          if (usedHeight + parts[index].extent > constraints.maxHeight) break;
          selected.add(index);
          usedHeight += parts[index].extent;
        }
        final allRequiredSelected = optionalOrder.isEmpty
            ? selected.length == parts.length
            : selected.length == requiredOrder.length;
        final navHeight = navigation?.heightFor(context, constraints.maxWidth);
        final showNavigation =
            navigation != null &&
            allRequiredSelected &&
            usedHeight + 10 + navHeight! <= constraints.maxHeight;
        final reservedNavHeight = showNavigation ? 10.0 + navHeight : 0.0;
        if (allRequiredSelected) {
          for (final index in optionalOrder) {
            if (usedHeight + reservedNavHeight + parts[index].extent <=
                constraints.maxHeight) {
              selected.add(index);
              usedHeight += parts[index].extent;
            }
          }
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < parts.length; index++)
              if (selected.contains(index))
                SizedBox(
                  height: parts[index].extent,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: parts[index].gap),
                    child: parts[index].child,
                  ),
                ),
            if (showNavigation) ...[
              const Spacer(),
              const SizedBox(height: 10),
              navigation,
            ],
          ],
        );
      },
    );
  }
}

class _WidgetPreviewProgressBar extends StatelessWidget {
  final double progress;
  final double height;

  const _WidgetPreviewProgressBar({
    required this.progress,
    this.height = 5,
  });

  @override
  Widget build(BuildContext context) {
    final payload = _WidgetPreviewTheme.maybeOf(context);
    final cs = Theme.of(context).colorScheme;
    final clamped = progress.clamp(0.0, 1.0).toDouble();
    final start = payload?.accentStart ?? cs.primary;
    final end = payload?.accentEnd ?? cs.secondary;
    final trackColor = cs.onSurface.withValues(alpha: 0.12);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: trackColor),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: clamped,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [start, end]),
                  borderRadius: BorderRadius.circular(height / 2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WidgetPreviewStatusPill extends StatelessWidget {
  final String label;
  final bool accentTone;

  const _WidgetPreviewStatusPill({
    required this.label,
    this.accentTone = false,
  });

  @override
  Widget build(BuildContext context) {
    final payload = _WidgetPreviewTheme.maybeOf(context);
    final cs = Theme.of(context).colorScheme;
    final radius = payload?.controlRadiusDp.toDouble() ?? 8.0;
    final bg = accentTone
        ? cs.primary.withValues(alpha: 0.14)
        : cs.onSurface.withValues(alpha: 0.08);
    final effectiveBg = Color.alphaBlend(
      bg,
      payload?.background ?? cs.surface,
    );
    final fg = appReadableForeground(
      effectiveBg,
      accentTone ? cs.primary : cs.onSurfaceVariant,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: (accentTone ? cs.primary : cs.outlineVariant).withValues(
            alpha: 0.30,
          ),
          width: 0.45,
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10,
          color: fg,
          fontWeight: FontWeight.normal,
        ),
      ),
    );
  }
}

class _WidgetPreviewTodoBody extends StatelessWidget {
  const _WidgetPreviewTodoBody();

  @override
  Widget build(BuildContext context) {
    final maxLines = _WidgetPreviewDensityScope.maxLinesOf(context);
    final useRealData = _WidgetPreviewDataScope.isRealData(context);
    final locale = I18n.current;
    final List<String> itemTitles;
    final String summaryText;
    if (useRealData) {
      final todoProvider = _watchOptionalProvider<TodoProvider>(context);
      final todayTodos = todoProvider?.visibleTodayTodos(DateTime.now()) ?? [];
      if (todayTodos.isEmpty) {
        itemTitles = [
          switch (locale) {
            AppLocale.zh => '今日暂无待办',
            AppLocale.en => 'No open tasks today',
          },
        ];
      } else {
        itemTitles = todayTodos.take(3).map((t) => t.title).toList();
      }
      summaryText = switch (locale) {
        AppLocale.zh => '共 ${todayTodos.length} 项待办',
        AppLocale.en => '${todayTodos.length} tasks today',
      };
    } else {
      itemTitles = [
        WidgetUiCopy.todoItem1,
        WidgetUiCopy.todoItem2,
        WidgetUiCopy.todoItem3,
      ];
      summaryText = WidgetUiCopy.todoSummaryCount;
    }
    final rows = [
      _WidgetPreviewTodoRow(text: itemTitles[0]),
      if (maxLines >= 2 && itemTitles.length > 1)
        _WidgetPreviewTodoRow(text: itemTitles[1]),
      if (maxLines >= 3 && itemTitles.length > 2)
        _WidgetPreviewTodoRow(text: itemTitles[2]),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final summary = _WidgetPreviewLine(
          icon: Icons.checklist_rtl_outlined,
          text: summaryText,
        );
        final add = _WidgetPreviewQuickAdd(label: WidgetUiCopy.todoQuickAdd);
        return _WidgetPreviewParts(
          parts: [
            for (var i = 0; i < rows.length; i++)
              _WidgetPreviewPart(
                priority: i,
                child: Padding(
                  padding: EdgeInsets.only(top: i > 0 ? 7 : 0),
                  child: rows[i],
                ),
                height:
                    rows[i].heightFor(context, constraints.maxWidth) +
                    (i > 0 ? 7 : 0),
              ),
            if (maxLines >= 3) ...[
              _WidgetPreviewPart(
                priority: rows.length,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: summary,
                ),
                height: summary.heightFor(context, constraints.maxWidth) + 8,
              ),
              _WidgetPreviewPart(
                priority: rows.length + 1,
                child: add,
                height: add.heightFor(context, constraints.maxWidth),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _WidgetPreviewFocusBody extends StatelessWidget {
  const _WidgetPreviewFocusBody();

  static List<_WidgetPreviewMetric> metricsFor(
    BuildContext context,
    int maxLines,
    double width,
  ) {
    final cs = Theme.of(context).colorScheme;
    final useRealData = _WidgetPreviewDataScope.isRealData(context);
    final String sessionsVal;
    final String minutesVal;
    final String nextVal;
    if (useRealData) {
      final pomodoro = _watchOptionalProvider<PomodoroProvider>(context);
      final now = DateTime.now();
      final totalSecs =
          pomodoro
              ?.focusSessionsForDate(now)
              .fold<int>(0, (sum, s) => sum + s.durationSeconds) ??
          0;
      sessionsVal = '${pomodoro?.sessionCountToday ?? 0}';
      minutesVal = '${totalSecs ~/ 60}';
      nextVal = '${(pomodoro?.effectiveFocusDuration ?? 1500) ~/ 60}';
    } else {
      sessionsVal = '2';
      minutesVal = '50';
      nextVal = '25';
    }
    final metrics = [
      _WidgetPreviewMetric(
        value: sessionsVal,
        label: WidgetUiCopy.focusMetricSessions,
        color: cs.primary,
      ),
      _WidgetPreviewMetric(
        value: minutesVal,
        label: WidgetUiCopy.focusMetricDuration,
        color: cs.primary,
      ),
      _WidgetPreviewMetric(
        value: nextVal,
        label: WidgetUiCopy.focusMetricNext,
        color: cs.primary,
      ),
    ];
    final allMetricsFit =
        maxLines > 1 &&
        metrics.every((metric) => metric.widthFor(context) <= width / 3);
    return allMetricsFit
        ? metrics
        : [
            _WidgetPreviewMetric(
              value: nextVal,
              label: WidgetUiCopy.focusTimerUnit,
              color: cs.primary,
              inline: true,
            ),
          ];
  }

  @override
  Widget build(BuildContext context) {
    final maxLines = _WidgetPreviewDensityScope.maxLinesOf(context);
    final useRealData = _WidgetPreviewDataScope.isRealData(context);
    final locale = I18n.current;
    final pomodoro = useRealData
        ? _watchOptionalProvider<PomodoroProvider>(context)
        : null;
    final focusState =
        pomodoro?.state ??
        const PomodoroState(
          remainingSeconds: 16 * 60,
          totalSeconds: 25 * 60,
          isRunning: true,
          type: PomodoroType.focus,
          completedSessions: 2,
        );
    final progressRatio = useRealData && pomodoro == null
        ? 0.0
        : widgetFocusProgressRatio(focusState);
    final stateLabel = useRealData && pomodoro == null
        ? widgetFocusStateLabel(
            const PomodoroState(
              remainingSeconds: 25 * 60,
              totalSeconds: 25 * 60,
              isRunning: false,
              type: PomodoroType.focus,
              completedSessions: 0,
            ),
            locale: locale,
          )
        : widgetFocusStateLabel(focusState, locale: locale);
    final buttonLabel = useRealData && pomodoro != null
        ? (focusState.isRunning
              ? switch (locale) {
                  AppLocale.zh => '暂停专注',
                  AppLocale.en => 'Pause Focus',
                }
              : progressRatio > 0 && progressRatio < 1.0
              ? switch (locale) {
                  AppLocale.zh => '继续专注',
                  AppLocale.en => 'Resume Focus',
                }
              : WidgetUiCopy.focusStartButton)
        : WidgetUiCopy.focusStartButton;

    return LayoutBuilder(
      builder: (context, constraints) {
        final displayed = metricsFor(context, maxLines, constraints.maxWidth);
        final columnWidth = constraints.maxWidth / displayed.length;
        final metricHeight = displayed
            .map((metric) => metric.heightFor(context, columnWidth))
            .reduce((a, b) => a > b ? a : b);
        final start = _WidgetPreviewQuickAdd(
          label: buttonLabel,
          fontSize: 12,
          primary: true,
        );
        final stateHeight =
            (_widgetPreviewTextSize(context, stateLabel, 10).height + 8).clamp(
              22.0,
              40.0,
            );
        final details = useRealData
            ? [
                _WidgetPreviewLine(
                  icon: Icons.timer_outlined,
                  text: pomodoro != null
                      ? nextFocusWidgetLabel(pomodoro, locale: locale)
                      : WidgetUiCopy.focusLine1,
                ),
                if (maxLines >= 3 && (focusState.taskName?.isNotEmpty ?? false))
                  _WidgetPreviewLine(
                    icon: Icons.play_circle_outline,
                    text: focusState.taskName!,
                  ),
              ]
            : [
                _WidgetPreviewLine(
                  icon: Icons.timer_outlined,
                  text: WidgetUiCopy.focusLine1,
                ),
                if (maxLines >= 3)
                  _WidgetPreviewLine(
                    icon: Icons.play_circle_outline,
                    text: WidgetUiCopy.focusLine2,
                  ),
                if (maxLines >= 3)
                  _WidgetPreviewLine(
                    icon: Icons.touch_app_outlined,
                    text: WidgetUiCopy.focusLine3,
                  ),
              ];
        return _WidgetPreviewParts(
          parts: [
            _WidgetPreviewPart(
              height: metricHeight,
              child: Row(
                children: [
                  for (final metric in displayed) Expanded(child: metric),
                ],
              ),
            ),
            if (maxLines >= 2) ...[
              _WidgetPreviewPart(
                optional: true,
                priority: 10,
                height: stateHeight + 6,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      _WidgetPreviewStatusPill(
                        label: stateLabel,
                        accentTone: focusState.isRunning,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _WidgetPreviewProgressBar(
                          progress: progressRatio,
                          height: 5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _WidgetPreviewPart(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: start,
                ),
                height: start.heightFor(context, constraints.maxWidth) + 8,
              ),
              for (var i = 0; i < details.length; i++)
                _WidgetPreviewPart(
                  child: Padding(
                    padding: EdgeInsets.only(top: i == 0 ? 8 : 0),
                    child: details[i],
                  ),
                  height:
                      details[i].heightFor(context, constraints.maxWidth) +
                      (i == 0 ? 8 : 0),
                ),
            ],
          ],
        );
      },
    );
  }
}

class _WidgetPreviewHabitBody extends StatelessWidget {
  const _WidgetPreviewHabitBody();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final payload = _WidgetPreviewTheme.maybeOf(context);
    final percentColor =
        payload != null && _isOpaquePreviewMetricCandidate(payload)
        ? appReadableForeground(payload.background, cs.primary)
        : cs.primary;
    final maxLines = _WidgetPreviewDensityScope.maxLinesOf(context);
    final useRealData = _WidgetPreviewDataScope.isRealData(context);
    final locale = I18n.current;
    final int percentValue;
    final double ratioValue;
    final String firstLineText;
    final String streakLineText;
    final List<({String label, bool done})> checkChips;
    if (useRealData) {
      final habitProvider = _watchOptionalProvider<HabitProvider>(context);
      final now = DateTime.now();
      final active =
          habitProvider?.habits.where((h) => h.activeForDate(now)).toList() ??
          const [];
      final completed = active
          .where((h) => h.isCompletedForDate(now))
          .toList();
      percentValue = widgetHabitCompletionPercent(
        activeCount: active.length,
        completedCount: completed.length,
      );
      ratioValue = widgetHabitCompletionRatio(
        activeCount: active.length,
        completedCount: completed.length,
      );
      final ratioLabel = widgetHabitSummaryRatioText(
        activeCount: active.length,
        completedCount: completed.length,
      );
      firstLineText = active.isEmpty
          ? switch (locale) {
              AppLocale.zh => '今日暂无活跃习惯',
              AppLocale.en => 'No active habits today',
            }
          : '$ratioLabel · ${active.first.name}';
      final streak = habitProvider?.longestCurrentStreak ?? 0;
      streakLineText = switch (locale) {
        AppLocale.zh => '最长连续 $streak 天',
        AppLocale.en => 'Best streak: ${streak}d',
      };
      checkChips = [
        for (final h in active.take(3))
          (
            label: '${h.isCompletedForDate(now) ? '✓' : '○'} ${h.name}',
            done: h.isCompletedForDate(now),
          ),
      ];
    } else {
      percentValue = 80;
      ratioValue = 0.80;
      firstLineText = WidgetUiCopy.habitLine1;
      streakLineText = WidgetUiCopy.habitLine2;
      checkChips = switch (locale) {
        AppLocale.zh => const [
          (label: '✓ 晨间阅读', done: true),
          (label: '✓ 运动打卡', done: true),
          (label: '○ 23:00 早睡', done: false),
        ],
        AppLocale.en => const [
          (label: '✓ Reading', done: true),
          (label: '✓ Workout', done: true),
          (label: '○ Sleep', done: false),
        ],
      };
    }
    final percentText = '$percentValue%';
    return LayoutBuilder(
      builder: (context, constraints) {
        final button = _WidgetPreviewQuickAdd(
          label: WidgetUiCopy.habitCheckInButton,
        );
        final buttonHeight = button.heightFor(context, constraints.maxWidth);
        final percentWidth = _widgetPreviewTextSize(
          context,
          percentText,
          14,
        ).width;
        final inlinePercent = percentWidth + 24 < constraints.maxWidth;
        final percentHeight = _widgetPreviewTextSize(
          context,
          percentText,
          14,
        ).height;
        const percentSpacing = 6.0;
        final reservedPercentWidth = inlinePercent
            ? percentWidth + percentSpacing
            : 0.0;
        final titleWidth = (constraints.maxWidth - reservedPercentWidth).clamp(
          0.0,
          double.infinity,
        );
        final titleHeight = _widgetPreviewTextSize(
          context,
          WidgetUiCopy.habitTitle,
          11,
          width: titleWidth,
          maxLines: null,
        ).height;
        final summaryHeight = inlinePercent
            ? (titleHeight > percentHeight ? titleHeight : percentHeight)
            : titleHeight;
        final summary = _WidgetPreviewPart(
          priority: 1,
          height: summaryHeight,
          gap: 6,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  WidgetUiCopy.habitTitle,
                  softWrap: true,
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ),
              if (inlinePercent) ...[
                const SizedBox(width: percentSpacing),
                Text(
                  percentText,
                  style: TextStyle(
                    fontSize: 14,
                    color: percentColor,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ],
            ],
          ),
        );
        // Android also keeps the summary when even one check-in cannot fit.
        if (buttonHeight > constraints.maxHeight) {
          return _WidgetPreviewParts(
            parts: [
              _WidgetPreviewPart(child: summary.child, height: summary.height),
            ],
          );
        }
        final first = _WidgetPreviewLine(
          icon: Icons.self_improvement_outlined,
          text: firstLineText,
        );
        final streak = _WidgetPreviewLine(
          icon: Icons.local_fire_department_outlined,
          text: streakLineText,
        );
        final chipHeight = checkChips.isEmpty
            ? 0.0
            : _widgetPreviewTextSize(
                    context,
                    checkChips.first.label,
                    10,
                  ).height +
                  6;
        final progressSectionHeight =
            5.0 + (checkChips.isNotEmpty ? 6.0 + chipHeight : 0.0);
        return _WidgetPreviewParts(
          parts: [
            summary,
            _WidgetPreviewPart(
              priority: 2,
              child: first,
              height: first.heightFor(context, constraints.maxWidth),
              gap: 6,
            ),
            if (maxLines >= 2)
              _WidgetPreviewPart(
                priority: 3,
                child: streak,
                height: streak.heightFor(context, constraints.maxWidth),
                gap: 6,
              ),
            _WidgetPreviewPart(
              optional: true,
              priority: 10,
              height: progressSectionHeight,
              gap: 6,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _WidgetPreviewProgressBar(progress: ratioValue, height: 5),
                  if (checkChips.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        for (var i = 0; i < checkChips.length; i++) ...[
                          if (i > 0) const SizedBox(width: 4),
                          Flexible(
                            child: _WidgetPreviewStatusPill(
                              label: checkChips[i].label,
                              accentTone: checkChips[i].done,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
            _WidgetPreviewPart(
              priority: 0,
              child: button,
              height: buttonHeight,
            ),
          ],
        );
      },
    );
  }
}

class _WidgetPreviewCalendarBody extends StatelessWidget {
  const _WidgetPreviewCalendarBody();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxLines = _WidgetPreviewDensityScope.maxLinesOf(context);
    final useRealData = _WidgetPreviewDataScope.isRealData(context);
    final locale = I18n.current;
    final prefsProvider = _watchOptionalProvider<PreferencesProvider>(context);
    final firstDayOfWeek = CalendarDateNavigation.normalizeFirstDayOfWeek(
      prefsProvider?.firstDayOfWeek ?? 1,
    );
    final now = DateTime.now();
    final year = useRealData ? now.year : 2026;
    final month = useRealData ? now.month : 5;
    final todayDay = useRealData ? now.day : 17;
    final daysInMonth = DateUtils.getDaysInMonth(year, month);
    final focusDate = DateTime(year, month, todayDay);
    final startOffset = (DateTime.utc(year, month).weekday - firstDayOfWeek) % 7;
    final totalWeeks = ((startOffset + daysInMonth) / 7).ceil();
    final currentWeekIndex = (startOffset + todayDay - 1) ~/ 7;
    final visibleWeeks = switch (maxLines) {
      1 => [currentWeekIndex],
      2 => [
        currentWeekIndex - 1,
        currentWeekIndex,
        currentWeekIndex + 1,
        currentWeekIndex + 2,
      ].where((index) => index >= 0 && index < totalWeeks).toList(),
      _ => List.generate(totalWeeks, (index) => index),
    };
    final weekLabels = [
      for (final iso in CalendarDateNavigation.orderedWeekdays(firstDayOfWeek))
        WidgetUiCopy.calendarWeekLabels[iso - 1],
    ];
    final monthWeeks = List.generate(
      totalWeeks,
      (row) => List<int?>.generate(7, (col) {
        final day = row * 7 + col - startOffset + 1;
        return day >= 1 && day <= daysInMonth ? day : null;
      }),
    );
    final lunarSummary = homeWidgetCalendarSummary(focusDate, locale: locale);
    final holidayBadge = homeWidgetCalendarDayBadge(focusDate, locale: locale);
    return LayoutBuilder(
      builder: (context, constraints) {
        final cellWidth = constraints.maxWidth / 7;
        final dateSizes = [
          for (var day = 1; day <= daysInMonth; day++)
            _widgetPreviewTextSize(context, '$day', 10),
        ];
        final labelSizes = [
          for (final label in weekLabels)
            _widgetPreviewTextSize(context, label, 10),
        ];
        final rowHeight = dateSizes
            .map((size) => size.height + 4)
            .fold(20.0, (height, next) => height > next ? height : next);
        final weekdayHeight = labelSizes
            .map((size) => size.height)
            .fold(0.0, (height, next) => height > next ? height : next);
        final today = _WidgetPreviewQuickAdd(label: WidgetUiCopy.calendarToday);
        final todayWidth =
            _widgetPreviewTextSize(
              context,
              WidgetUiCopy.calendarToday,
              11,
            ).width +
            20.9;
        final headerHeight = today.heightFor(context, todayWidth);
        final cellsFit =
            dateSizes.every((size) => size.width + 8 <= cellWidth) &&
            labelSizes.every((size) => size.width <= cellWidth);
        if (!cellsFit ||
            headerHeight + 7 + weekdayHeight + 4 + rowHeight + 3 >
                constraints.maxHeight) {
          final currentDateStr = useRealData
              ? '$year-${month.toString().padLeft(2, '0')}-${todayDay.toString().padLeft(2, '0')}'
              : WidgetUiCopy.calendarCurrentDate;
          final currentDayStr = useRealData
              ? '$todayDay'
              : WidgetUiCopy.calendarCurrentDay;
          final fullDateHeight = _widgetPreviewTextSize(
            context,
            currentDateStr,
            11,
            width: constraints.maxWidth - 19,
            maxLines: null,
          ).height;
          final compactDate = fullDateHeight > constraints.maxHeight;
          final dateLabel = compactDate ? currentDayStr : currentDateStr;
          final height = compactDate
              ? _widgetPreviewTextSize(
                  context,
                  dateLabel,
                  11,
                  width: constraints.maxWidth,
                  maxLines: null,
                ).height
              : fullDateHeight;
          return _WidgetPreviewParts(
            parts: [
              _WidgetPreviewPart(
                height: height > 13 ? height : 13,
                child: Row(
                  children: [
                    if (!compactDate) ...[
                      Icon(
                        Icons.calendar_today_outlined,
                        size: 13,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        dateLabel,
                        softWrap: true,
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }
        final lunarTextHeight =
            _widgetPreviewTextSize(context, lunarSummary, 10).height + 6;
        return _WidgetPreviewParts(
          parts: [
            _WidgetPreviewPart(
              height: headerHeight,
              gap: 7,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      WidgetUiCopy.calendarMonthHeader(year, month),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(width: todayWidth, child: today),
                ],
              ),
            ),
            _WidgetPreviewPart(
              height: weekdayHeight,
              gap: 4,
              child: Row(
                children: [
                  for (final label in weekLabels)
                    Expanded(
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 10,
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            for (final index in visibleWeeks)
              _WidgetPreviewPart(
                priority: index == currentWeekIndex
                    ? 0
                    : (index - currentWeekIndex).abs(),
                height: rowHeight,
                gap: 3,
                child: Row(
                  children: [
                    for (final day in monthWeeks[index])
                      Expanded(
                        child: _WidgetPreviewCalendarCell(
                          day: day,
                          isToday: day == todayDay,
                          isHoliday:
                              day != null &&
                              HolidayCalendar.isHoliday(
                                DateTime(year, month, day),
                              ),
                          isMakeup:
                              day != null &&
                              HolidayCalendar.isWorkMakeupDay(
                                DateTime(year, month, day),
                              ),
                        ),
                      ),
                  ],
                ),
              ),
            _WidgetPreviewPart(
              optional: true,
              priority: 100,
              height: lunarTextHeight,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      lunarSummary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ),
                  if (holidayBadge != null) ...[
                    const SizedBox(width: 6),
                    _WidgetPreviewStatusPill(
                      label: holidayBadge,
                      accentTone: true,
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _WidgetPreviewCalendarCell extends StatelessWidget {
  final int? day;
  final bool isToday;
  final bool isHoliday;
  final bool isMakeup;

  const _WidgetPreviewCalendarCell({
    required this.day,
    this.isToday = false,
    this.isHoliday = false,
    this.isMakeup = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final payload = _WidgetPreviewTheme.maybeOf(context);
    final cellRadius =
        (payload?.controlRadiusDp.toDouble()) ??
        _WidgetPreviewTheme.of(context).controlRadiusDp.toDouble();
    final todayForeground =
        payload != null &&
            _isOpaquePreviewMetricCandidate(payload) &&
            cs.primary.a == 1.0
        ? appReadableForeground(cs.primary, cs.onPrimary)
        : cs.onPrimary;
    return Container(
      constraints: const BoxConstraints(minHeight: 20),
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(vertical: 2),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isToday ? cs.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(cellRadius),
      ),
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Text(
            day == null ? '' : '$day',
            maxLines: 1,
            style: TextStyle(
              fontSize: 10,
              color: isToday ? todayForeground : cs.onSurface,
              fontWeight: FontWeight.normal,
            ),
          ),
          if (isToday)
            Positioned(
              bottom: -2,
              child: Container(
                width: 3,
                height: 3,
                decoration: BoxDecoration(
                  color: todayForeground,
                  shape: BoxShape.circle,
                ),
              ),
            )
          else if (isHoliday || isMakeup)
            Positioned(
              top: 0,
              right: -4,
              child: Container(
                width: 3,
                height: 3,
                decoration: BoxDecoration(
                  color: isHoliday ? cs.primary : cs.secondary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _WidgetPreviewScheduleBody extends StatelessWidget {
  const _WidgetPreviewScheduleBody();

  @override
  Widget build(BuildContext context) {
    final useRealData = _WidgetPreviewDataScope.isRealData(context);
    final locale = I18n.current;
    final List<String> items;
    if (useRealData) {
      final calendar = _watchOptionalProvider<CalendarProvider>(context);
      final todos = _watchOptionalProvider<TodoProvider>(context);
      final habits = _watchOptionalProvider<HabitProvider>(context);
      final pomodoro = _watchOptionalProvider<PomodoroProvider>(context);
      final anniversaries = _watchOptionalProvider<AnniversaryProvider>(
        context,
      );
      final courses = _watchOptionalProvider<CourseProvider>(context);
      final diaries = _watchOptionalProvider<DiaryProvider>(context);
      final countdowns = _watchOptionalProvider<CountdownProvider>(context);
      final goals = _watchOptionalProvider<GoalProvider>(context);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final events = calendar == null
          ? const <String>[]
          : homeWidgetScheduleEvents(
              calendar.buildEventsForDateSnapshot(
                today,
                todos?.todos ?? const [],
                habits?.habits ?? const [],
                pomodoro?.focusSessionsForDate(today) ?? const [],
                Theme.of(context).colorScheme,
                anniversaries: anniversaries?.itemsAt(today),
                courses: courses?.coursesOfDate(today),
                courseSettings: courses?.settings,
                diaries: diaries?.entries,
                countdowns: countdowns?.items,
                goals: goals?.activeGoals,
                now: now,
              ),
            ).take(3).map(homeWidgetScheduleEventLabel).toList();
      items = events.isNotEmpty
          ? events
          : [
              switch (locale) {
                AppLocale.zh => '今日暂无日程安排',
                AppLocale.en => 'No schedule events today',
              },
            ];
    } else {
      items = [
        WidgetUiCopy.scheduleItem1,
        WidgetUiCopy.scheduleItem2,
        WidgetUiCopy.scheduleItem3,
      ];
    }
    const icons = [
      Icons.notifications_active_outlined,
      Icons.event_note_outlined,
      Icons.event_available_outlined,
    ];
    return _WidgetPreviewLineList(
      lines: [
        for (var i = 0; i < items.length; i++)
          _WidgetPreviewLine(icon: icons[i % icons.length], text: items[i]),
      ],
    );
  }
}

class _WidgetPreviewGoalBody extends StatelessWidget {
  const _WidgetPreviewGoalBody();

  @override
  Widget build(BuildContext context) {
    final useRealData = _WidgetPreviewDataScope.isRealData(context);
    final locale = I18n.current;
    final List<({String text, double progress, String badge})> entries;
    if (useRealData) {
      final goals = _watchOptionalProvider<GoalProvider>(context)?.activeGoals;
      if (goals == null || goals.isEmpty) {
        entries = [
          (
            text: switch (locale) {
              AppLocale.zh => '暂无进行中的目标',
              AppLocale.en => 'No active goals',
            },
            progress: 0.0,
            badge: '0%',
          ),
        ];
      } else {
        entries = [
          for (final g in goals.take(3))
            (
              text: '${g.title} · ${(g.computedProgress * 100).round()}%',
              progress: g.computedProgress.clamp(0.0, 1.0).toDouble(),
              badge: '${(g.computedProgress * 100).round()}%',
            ),
        ];
      }
    } else {
      entries = [
        (text: WidgetUiCopy.goalItem1, progress: 0.68, badge: '68%'),
        (text: WidgetUiCopy.goalItem2, progress: 0.50, badge: '50%'),
        (text: WidgetUiCopy.goalItem3, progress: 1.0, badge: '100%'),
      ];
    }
    const icons = [
      Icons.flag_outlined,
      Icons.trending_up_outlined,
      Icons.check_circle_outline,
    ];
    return _WidgetPreviewLineList(
      lines: [
        for (var i = 0; i < entries.length; i++)
          _WidgetPreviewLine(
            icon: icons[i % icons.length],
            text: entries[i].text,
          ),
      ],
      progressItems: [
        for (final entry in entries)
          (progress: entry.progress, badge: entry.badge),
      ],
    );
  }
}

class _WidgetPreviewCourseBody extends StatelessWidget {
  const _WidgetPreviewCourseBody();

  @override
  Widget build(BuildContext context) {
    final useRealData = _WidgetPreviewDataScope.isRealData(context);
    final locale = I18n.current;
    final List<String> items;
    if (useRealData) {
      final courseProvider = _watchOptionalProvider<CourseProvider>(context);
      final now = DateTime.now();
      final todayCourses = courseProvider?.coursesOfDate(now) ?? const [];
      if (todayCourses.isEmpty) {
        items = [
          switch (locale) {
            AppLocale.zh => '今日无课程安排',
            AppLocale.en => 'No classes today',
          },
        ];
      } else {
        final settings = courseProvider!.settings;
        items = [
          for (final c in todayCourses.take(3))
            '${settings.sectionTimeRangeLabel(c.startSection, c.sectionCount)} · ${c.name}${c.location.isEmpty ? '' : ' (${c.location})'}',
        ];
      }
    } else {
      items = [
        WidgetUiCopy.courseItem1,
        WidgetUiCopy.courseItem2,
        WidgetUiCopy.courseItem3,
      ];
    }
    const icons = [
      Icons.school_outlined,
      Icons.school_outlined,
      Icons.event_note_outlined,
    ];
    return _WidgetPreviewLineList(
      lines: [
        for (var i = 0; i < items.length; i++)
          _WidgetPreviewLine(icon: icons[i % icons.length], text: items[i]),
      ],
    );
  }
}

class _WidgetPreviewNoteBody extends StatelessWidget {
  const _WidgetPreviewNoteBody();

  @override
  Widget build(BuildContext context) {
    final useRealData = _WidgetPreviewDataScope.isRealData(context);
    final locale = I18n.current;
    final List<String> items;
    if (useRealData) {
      final notes = _watchOptionalProvider<NoteProvider>(context)?.activeNotes;
      if (notes == null || notes.isEmpty) {
        items = [
          switch (locale) {
            AppLocale.zh => '暂无活跃笔记',
            AppLocale.en => 'No active notes',
          },
        ];
      } else {
        items = [for (final n in notes.take(3)) n.titleFor(locale)];
      }
    } else {
      items = [
        WidgetUiCopy.noteItem1,
        WidgetUiCopy.noteItem2,
        WidgetUiCopy.noteItem3,
      ];
    }
    const icons = [
      Icons.edit_note_outlined,
      Icons.lightbulb_outline,
      Icons.menu_book_outlined,
    ];
    return _WidgetPreviewLineList(
      lines: [
        for (var i = 0; i < items.length; i++)
          _WidgetPreviewLine(icon: icons[i % icons.length], text: items[i]),
      ],
    );
  }
}

class _WidgetPreviewAnniversaryBody extends StatelessWidget {
  const _WidgetPreviewAnniversaryBody();

  @override
  Widget build(BuildContext context) {
    final useRealData = _WidgetPreviewDataScope.isRealData(context);
    final locale = I18n.current;
    final List<String> items;
    if (useRealData) {
      final provider = _watchOptionalProvider<AnniversaryProvider>(context);
      final now = DateTime.now();
      final list = provider?.itemsAt(now) ?? const [];
      if (list.isEmpty) {
        items = [
          switch (locale) {
            AppLocale.zh => '暂无纪念日记录',
            AppLocale.en => 'No anniversaries yet',
          },
        ];
      } else {
        items = [
          for (final a in list.take(3))
            '${a.title} · ${a.daysRemainingForDate(now)}d',
        ];
      }
    } else {
      items = [
        WidgetUiCopy.anniversaryItem1,
        WidgetUiCopy.anniversaryItem2,
        WidgetUiCopy.anniversaryItem3,
      ];
    }
    return _WidgetPreviewLineList(
      lines: [
        for (final text in items)
          _WidgetPreviewLine(icon: Icons.event_available_outlined, text: text),
      ],
    );
  }
}

class _WidgetPreviewDiaryBody extends StatelessWidget {
  const _WidgetPreviewDiaryBody();

  @override
  Widget build(BuildContext context) {
    final useRealData = _WidgetPreviewDataScope.isRealData(context);
    final locale = I18n.current;
    final List<String> items;
    if (useRealData) {
      final entries = _watchOptionalProvider<DiaryProvider>(context)?.entries;
      if (entries == null || entries.isEmpty) {
        items = [
          switch (locale) {
            AppLocale.zh => '暂无日记内容',
            AppLocale.en => 'No diary entries yet',
          },
        ];
      } else {
        items = [
          for (final e in entries.take(3))
            '${e.date.month}/${e.date.day} · ${e.titleFor(locale)}',
        ];
      }
    } else {
      items = [
        WidgetUiCopy.diaryItem1,
        WidgetUiCopy.diaryItem2,
        WidgetUiCopy.diaryItem3,
      ];
    }
    return _WidgetPreviewLineList(
      lines: [
        for (final text in items)
          _WidgetPreviewLine(icon: Icons.book_outlined, text: text),
      ],
    );
  }
}

class _WidgetPreviewLineList extends StatelessWidget {
  final List<_WidgetPreviewLine> lines;
  final List<({double progress, String badge})>? progressItems;

  const _WidgetPreviewLineList({
    required this.lines,
    this.progressItems,
  });

  @override
  Widget build(BuildContext context) {
    final maxLines = _WidgetPreviewDensityScope.maxLinesOf(context);
    final navigation = _WidgetPreviewListScope.navigationOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final candidates = lines.take(maxLines).toList(growable: false);
        final visible = <_WidgetPreviewLine>[];
        var usedHeight = 0.0;
        for (final line in candidates) {
          final rowHeight = line.heightFor(context, constraints.maxWidth);
          if (usedHeight + rowHeight > constraints.maxHeight) break;
          visible.add(line);
          usedHeight += rowHeight;
        }
        // Content wins over navigation. Never shrink enlarged text to fit.
        final navHeight = navigation?.heightFor(context, constraints.maxWidth);
        final showNavigation =
            navigation != null &&
            visible.length == candidates.length &&
            usedHeight + 10 + navHeight! <= constraints.maxHeight;
        final reservedNav = showNavigation ? 10.0 + navHeight : 0.0;
        final shownBars = progressItems != null &&
                visible.length == candidates.length
            ? progressItems!.take(visible.length).toList(growable: false)
            : const <({double progress, String badge})>[];
        final badgeHeight = shownBars.isEmpty
            ? 0.0
            : _widgetPreviewTextSize(
                    context,
                    shownBars.first.badge,
                    10,
                  ).height +
                  15.0;
        final showProgressBars =
            shownBars.isNotEmpty &&
            usedHeight + reservedNav + badgeHeight <= constraints.maxHeight;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...visible,
            if (showProgressBars) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  for (var i = 0; i < shownBars.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            shownBars[i].badge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              color: () {
                                final payload = _WidgetPreviewTheme.maybeOf(
                                  context,
                                );
                                final cs = Theme.of(context).colorScheme;
                                return payload != null &&
                                        _isOpaquePreviewMetricCandidate(payload)
                                    ? appReadableForeground(
                                        payload.background,
                                        cs.primary,
                                      )
                                    : cs.primary;
                              }(),
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                          const SizedBox(height: 3),
                          _WidgetPreviewProgressBar(
                            progress: shownBars[i].progress,
                            height: 5,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],
            if (showNavigation) ...[
              const Spacer(),
              const SizedBox(height: 10),
              navigation,
            ],
          ],
        );
      },
    );
  }
}

class _WidgetPreviewQuickAdd extends StatelessWidget {
  final String label;
  final double fontSize;
  final bool primary;

  const _WidgetPreviewQuickAdd({
    required this.label,
    this.fontSize = 11,
    this.primary = false,
  });

  double heightFor(BuildContext context, double width) {
    final height =
        _widgetPreviewTextSize(
          context,
          label,
          fontSize,
          width: width - 20.9,
          maxLines: null,
        ).height +
        10.9;
    return height > 24 ? height : 24;
  }

  @override
  Widget build(BuildContext context) {
    final payload = _WidgetPreviewTheme.of(context);
    final chipRadius = payload.controlRadiusDp.toDouble();
    final cs = Theme.of(context).colorScheme;
    final Color backgroundColor;
    final Color foregroundColor;
    if (primary) {
      backgroundColor = cs.primary;
      foregroundColor = appReadableForeground(backgroundColor, cs.onPrimary);
    } else {
      final chipTint = cs.primary.withValues(alpha: 0.1);
      backgroundColor = chipTint;
      final renderedBg = Color.alphaBlend(chipTint, payload.background);
      foregroundColor = appReadableForeground(renderedBg, cs.primary);
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(minHeight: 24),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(chipRadius),
          border: Border.all(
            color: cs.primary.withValues(alpha: 0.28),
            width: 0.45,
          ),
        ),
        child: Text(
          label,
          softWrap: true,
          style: TextStyle(
            color: foregroundColor,
            fontSize: fontSize,
            fontWeight: FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _WidgetPreviewLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _WidgetPreviewLine({required this.icon, required this.text});

  TextStyle _style(BuildContext context) => TextStyle(
    fontSize: 11,
    color: Theme.of(context).colorScheme.onSurfaceVariant,
    fontWeight: FontWeight.normal,
  );

  double heightFor(BuildContext context, double width) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: _widgetMeasurementStyle(
          context,
          DefaultTextStyle.of(context).style.merge(_style(context)),
        ),
      ),
      maxLines: null,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
      textHeightBehavior:
          DefaultTextStyle.of(context).textHeightBehavior ??
          DefaultTextHeightBehavior.maybeOf(context),
    )..layout(maxWidth: (width - 19).clamp(0.0, double.infinity));
    final height = painter.height < 13 ? 13.0 : painter.height;
    painter.dispose();
    return height + 4;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 13, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(child: Text(text, softWrap: true, style: _style(context))),
        ],
      ),
    );
  }
}

class _WidgetPreviewTodoRow extends StatelessWidget {
  final String text;

  const _WidgetPreviewTodoRow({required this.text});

  Size _controlSize(BuildContext context) {
    final size = _widgetPreviewTextSize(context, '○', 13);
    return Size(
      size.width + 4 > 22 ? size.width + 4 : 22,
      size.height + 4 > 22 ? size.height + 4 : 22,
    );
  }

  double heightFor(BuildContext context, double width) {
    final control = _controlSize(context);
    final textWidth = (width - control.width - 7).clamp(0.0, double.infinity);
    final title = _widgetPreviewTextSize(
      context,
      text,
      12,
      width: textWidth,
      maxLines: null,
    );
    return control.height > title.height ? control.height : title.height;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final boxRadius = _WidgetPreviewTheme.of(
      context,
    ).controlRadiusDp.toDouble();
    final controlSize = _controlSize(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: controlSize.width,
          height: controlSize.height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(boxRadius),
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.28),
              width: 0.45,
            ),
          ),
          child: Text(
            '○',
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 13,
              fontWeight: FontWeight.normal,
            ),
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            softWrap: true,
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurface,
              fontWeight: FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }
}

class _WidgetPreviewMetric extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  final bool inline;

  const _WidgetPreviewMetric({
    required this.value,
    required this.label,
    required this.color,
    this.inline = false,
  });

  double widthFor(BuildContext context) {
    final valueWidth = _widgetPreviewTextSize(context, value, 13).width;
    final labelWidth = _widgetPreviewTextSize(context, label, 10).width;
    return inline
        ? valueWidth + 4 + labelWidth
        : (valueWidth > labelWidth ? valueWidth : labelWidth);
  }

  double heightFor(BuildContext context, double width) {
    final valueSize = _widgetPreviewTextSize(context, value, 13, width: width);
    final labelWidth = inline
        ? (width - valueSize.width - 4).clamp(0.0, double.infinity)
        : width;
    final labelHeight = _widgetPreviewTextSize(
      context,
      label,
      10,
      width: labelWidth,
      maxLines: null,
    ).height;
    return inline
        ? (valueSize.height > labelHeight ? valueSize.height : labelHeight)
        : valueSize.height + labelHeight;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final payload = _WidgetPreviewTheme.maybeOf(context);
    final effectiveColor =
        payload != null && _isOpaquePreviewMetricCandidate(payload)
        ? appReadableForeground(payload.background, color)
        : color;
    final children = <Widget>[
      Text(
        value,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.normal,
          color: effectiveColor,
        ),
      ),
      if (inline) const SizedBox(width: 4),
      Text(
        label,
        softWrap: true,
        style: TextStyle(
          fontSize: 10,
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.normal,
        ),
      ),
    ];
    return inline
        ? Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              children[0],
              children[1],
              Flexible(child: children[2]),
            ],
          )
        : Column(children: children);
  }
}

class _WidgetPreviewNav extends StatelessWidget {
  final int selectedIndex;
  final Color accent;

  const _WidgetPreviewNav({required this.selectedIndex, required this.accent});

  double heightFor(BuildContext context, double width) {
    const spacing = DesignTokens.spaceSm;
    const runSpacing = 4.0;
    final availableWidth = (width - 0.9).clamp(0.0, double.infinity);
    var runWidth = 0.0;
    var runHeight = 0.0;
    var contentHeight = 0.0;
    for (final label in WidgetUiCopy.previewNavLabels) {
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: _widgetMeasurementStyle(
            context,
            DefaultTextStyle.of(context).style.merge(
              const TextStyle(fontSize: 11, fontWeight: FontWeight.normal),
            ),
          ),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        locale: Localizations.maybeLocaleOf(context),
        textHeightBehavior:
            DefaultTextStyle.of(context).textHeightBehavior ??
            DefaultTextHeightBehavior.maybeOf(context),
      )..layout();
      final itemWidth = painter.width;
      final itemHeight = painter.height;
      // Container border insets reduce Wrap's width by 0.45 on each side.
      if (runWidth > 0 && runWidth + spacing + itemWidth > availableWidth) {
        contentHeight += runHeight + runSpacing;
        runWidth = itemWidth;
        runHeight = itemHeight;
      } else {
        runWidth += (runWidth > 0 ? spacing : 0.0) + itemWidth;
        if (itemHeight > runHeight) runHeight = itemHeight;
      }
      painter.dispose();
    }
    contentHeight += runHeight + 10.9; // 5px padding + 0.45px border per side.
    return contentHeight < 30 ? 30 : contentHeight;
  }

  static Color _resolveSelectedNavForeground({
    required Color background,
    required Color accent,
    required Color unselectedForeground,
  }) {
    final effectiveAccent = Color.alphaBlend(accent, background);
    if (appContrastRatio(background, effectiveAccent) >= 4.5 &&
        effectiveAccent != unselectedForeground) {
      return accent;
    }

    final darkContrast = appContrastRatio(background, Colors.black);
    final lightContrast = appContrastRatio(background, Colors.white);
    final primaryTarget =
        darkContrast >= lightContrast ? Colors.black : Colors.white;
    final secondaryTarget =
        darkContrast >= lightContrast ? Colors.white : Colors.black;

    // Prefer a readable darker shade of the brand accent on light backgrounds
    // (or lighter shade on dark backgrounds).
    for (var t = 0.05; t <= 0.95; t += 0.05) {
      final candidate = Color.lerp(accent, primaryTarget, t)!;
      final effectiveCandidate = Color.alphaBlend(candidate, background);
      if (appContrastRatio(background, effectiveCandidate) >= 4.5 &&
          effectiveCandidate != unselectedForeground) {
        return candidate;
      }
    }

    for (var t = 0.05; t <= 0.95; t += 0.05) {
      final candidate = Color.lerp(accent, secondaryTarget, t)!;
      final effectiveCandidate = Color.alphaBlend(candidate, background);
      if (appContrastRatio(background, effectiveCandidate) >= 4.5 &&
          effectiveCandidate != unselectedForeground) {
        return candidate;
      }
    }

    final fallback = appReadableForeground(background, accent);
    if (fallback != unselectedForeground) {
      return fallback;
    }

    // Boundary fallback: never silently lose selection to a same-color fallback.
    return darkContrast >= lightContrast
        ? (unselectedForeground == const Color(0xFF111827)
            ? const Color(0xFF8B0000)
            : const Color(0xFF111827))
        : (unselectedForeground == Colors.white
            ? const Color(0xFFFFB4AB)
            : Colors.white);
  }

  @override
  Widget build(BuildContext context) {
    final labels = WidgetUiCopy.previewNavLabels;
    final cs = Theme.of(context).colorScheme;
    final payload = _WidgetPreviewTheme.of(context);
    final navRadius = payload.controlRadiusDp.toDouble();
    final effectiveNavBg = Color.alphaBlend(
      payload.navBackground,
      payload.background,
    );
    final unselectedForeground = appReadableForeground(
      effectiveNavBg,
      cs.onSurfaceVariant,
    );
    final selectedForeground = _resolveSelectedNavForeground(
      background: effectiveNavBg,
      accent: accent,
      unselectedForeground: unselectedForeground,
    );
    return Container(
      key: const ValueKey('widget_preview_navigation'),
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 30),
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: payload.navBackground,
        borderRadius: BorderRadius.circular(navRadius),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.18),
          width: 0.45,
        ),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceEvenly,
        spacing: DesignTokens.spaceSm,
        runSpacing: 4,
        children: [
          for (var i = 0; i < labels.length; i++)
            Semantics(
              selected: i == selectedIndex,
              child: Text(
                labels[i],
                textAlign: TextAlign.center,
                softWrap: false,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.normal,
                  color: i == selectedIndex
                      ? selectedForeground
                      : unselectedForeground,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _WidgetCatalogTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  const _WidgetCatalogTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(
              appSurfaceStyleOf(context)?.smallTileRadius ??
                  DesignTokens.radiusControl,
            ),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: DesignTokens.fontSizeBody,
                    fontWeight: FontWeight.normal,
                    color: cs.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
