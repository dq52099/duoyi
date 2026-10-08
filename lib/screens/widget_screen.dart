import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/i18n.dart';
import '../core/platform_info.dart';
import '../core/web_target.dart';
import '../core/widget_ui_copy.dart';
import '../providers/theme_provider.dart';
import '../services/android_widget_manager.dart';
import '../services/home_widget_service.dart';
import '../widgets/surface_components.dart';
import 'calendar_screen.dart';

Widget _widgetFeedback(ValueGetter<String> message) {
  return ValueListenableBuilder<AppLocale>(
    valueListenable: I18n.localeListenable,
    builder: (context, _, _) => Text(message()),
  );
}

typedef _WidgetCategory = WidgetCategory;

extension _WidgetCategoryX on _WidgetCategory {
  String get label => WidgetUiCopy.categoryLabel(this);
}

class _WidgetCatalogItem {
  final DuoyiWidgetKind kind;
  final _WidgetCategory category;
  final IconData icon;
  final Color color;
  final Widget Function(WidgetDisplayMode mode) previewBuilder;

  const _WidgetCatalogItem({
    required this.kind,
    required this.category,
    required this.icon,
    required this.color,
    required this.previewBuilder,
  });

  String get title => WidgetUiCopy.catalogTitle(kind);
  String get subtitle => WidgetUiCopy.catalogSubtitle(kind);
}

final List<_WidgetCatalogItem> _widgetCatalog = [
  _WidgetCatalogItem(
    kind: DuoyiWidgetKind.todo,
    category: _WidgetCategory.productivity,
    icon: Icons.checklist_rtl_outlined,
    color: Colors.blue,
    previewBuilder: (mode) => WidgetPreviewCard.todo(displayMode: mode),
  ),
  _WidgetCatalogItem(
    kind: DuoyiWidgetKind.focus,
    category: _WidgetCategory.productivity,
    icon: Icons.timer_outlined,
    color: Colors.redAccent,
    previewBuilder: (mode) => WidgetPreviewCard.focus(displayMode: mode),
  ),
  _WidgetCatalogItem(
    kind: DuoyiWidgetKind.habit,
    category: _WidgetCategory.life,
    icon: Icons.self_improvement_outlined,
    color: Colors.green,
    previewBuilder: (mode) => WidgetPreviewCard.habit(displayMode: mode),
  ),
  _WidgetCatalogItem(
    kind: DuoyiWidgetKind.calendar,
    category: _WidgetCategory.life,
    icon: Icons.calendar_month_outlined,
    color: Colors.indigo,
    previewBuilder: (mode) => WidgetPreviewCard.calendar(displayMode: mode),
  ),
  _WidgetCatalogItem(
    kind: DuoyiWidgetKind.schedule,
    category: _WidgetCategory.productivity,
    icon: Icons.event_note_outlined,
    color: Colors.cyan,
    previewBuilder: (mode) => WidgetPreviewCard.schedule(displayMode: mode),
  ),
  _WidgetCatalogItem(
    kind: DuoyiWidgetKind.goal,
    category: _WidgetCategory.productivity,
    icon: Icons.flag_outlined,
    color: Colors.orange,
    previewBuilder: (mode) => WidgetPreviewCard.goal(displayMode: mode),
  ),
  _WidgetCatalogItem(
    kind: DuoyiWidgetKind.course,
    category: _WidgetCategory.productivity,
    icon: Icons.school_outlined,
    color: Colors.orange,
    previewBuilder: (mode) => WidgetPreviewCard.course(displayMode: mode),
  ),
  _WidgetCatalogItem(
    kind: DuoyiWidgetKind.note,
    category: _WidgetCategory.life,
    icon: Icons.edit_note_outlined,
    color: Colors.purple,
    previewBuilder: (mode) => WidgetPreviewCard.note(displayMode: mode),
  ),
  _WidgetCatalogItem(
    kind: DuoyiWidgetKind.anniversary,
    category: _WidgetCategory.life,
    icon: Icons.event_available_outlined,
    color: Colors.pink,
    previewBuilder: (mode) => WidgetPreviewCard.anniversary(displayMode: mode),
  ),
  _WidgetCatalogItem(
    kind: DuoyiWidgetKind.diary,
    category: _WidgetCategory.life,
    icon: Icons.book_outlined,
    color: Colors.teal,
    previewBuilder: (mode) => WidgetPreviewCard.diary(displayMode: mode),
  ),
];

class WidgetScreen extends StatefulWidget {
  const WidgetScreen({super.key});

  @override
  State<WidgetScreen> createState() => _WidgetScreenState();
}

class _WidgetScreenState extends State<WidgetScreen>
    with WidgetsBindingObserver {
  static const _displayModeKey = 'duoyi_widget_display_mode';
  WidgetDisplayMode _displayMode = WidgetDisplayMode.standard;
  AndroidWidgetPinResult? _pinSupport;
  bool _checkingPinSupport = true;
  bool _canOpenWidgetSettings = false;
  bool _refreshingData = false;
  _WidgetCategory _selectedCategory = _WidgetCategory.all;
  bool _userChangedDisplayMode = false;
  int _pinSupportSeq = 0;
  int _displayModeSeq = 0;
  bool _isUpdatingDisplayMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    I18n.localeListenable.addListener(_onLocaleChanged);
    _loadDisplayMode();
    _loadPinSupport();
  }

  @override
  void dispose() {
    I18n.localeListenable.removeListener(_onLocaleChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onLocaleChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadPinSupport();
    }
  }

  Future<void> _loadDisplayMode() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_displayModeKey);
    if (!mounted || _userChangedDisplayMode) return;
    setState(() {
      _displayMode = WidgetDisplayMode.fromId(value);
    });
  }

  Future<void> _loadPinSupport() async {
    final seq = ++_pinSupportSeq;
    final support = await AndroidWidgetManager.checkPinSupport();
    final canOpenSettings = await AndroidWidgetManager.canOpenWidgetSettings();
    if (!mounted || seq != _pinSupportSeq) return;
    setState(() {
      _pinSupport = support;
      _checkingPinSupport = false;
      _canOpenWidgetSettings = canOpenSettings;
    });
  }

  Future<void> _setDisplayMode(WidgetDisplayMode mode) async {
    if (_isUpdatingDisplayMode) return;
    _userChangedDisplayMode = true;
    final seq = ++_displayModeSeq;
    setState(() {
      _displayMode = mode;
      _isUpdatingDisplayMode = true;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_displayModeKey, mode.id);
      final isWeb = kIsWeb || WebTarget.isDesktopWebBuild;
      bool homeWidgetSynced = true;
      int? appliedCount = 0;
      if (!isWeb) {
        homeWidgetSynced = await HomeWidgetService.setDisplayMode(mode.id);
        appliedCount =
            await AndroidWidgetManager.applyDisplayModeToExistingWidgets(
              mode.androidStyle,
            );
      }
      if (!mounted || seq != _displayModeSeq) return;
      final nativeSynced = isWeb || appliedCount != null;
      if (!homeWidgetSynced || !nativeSynced) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: _widgetFeedback(() => WidgetUiCopy.styleSyncFailed),
            action: SnackBarAction(
              label: WidgetUiCopy.actionRetry,
              onPressed: () => _setDisplayMode(mode),
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: _widgetFeedback(
              () => WidgetUiCopy.styleSyncSuccess(mode.label),
            ),
          ),
        );
      }
    } catch (_) {
      if (!mounted || seq != _displayModeSeq) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: _widgetFeedback(() => WidgetUiCopy.styleSyncFailed),
          action: SnackBarAction(
            label: WidgetUiCopy.actionRetry,
            onPressed: () => _setDisplayMode(mode),
          ),
        ),
      );
    } finally {
      if (mounted && seq == _displayModeSeq) {
        setState(() => _isUpdatingDisplayMode = false);
      }
    }
  }

  Future<void> _openWidgetSettings() async {
    final opened = await AndroidWidgetManager.openWidgetSettings();
    if (!mounted) return;
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

  Future<void> _refreshWidgetData() async {
    if (_refreshingData) return;
    setState(() => _refreshingData = true);
    try {
      final success = await HomeWidgetService.refreshDashboardData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: _widgetFeedback(
            () => success
                ? WidgetUiCopy.refreshSuccess
                : WidgetUiCopy.refreshFailed,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: _widgetFeedback(() => WidgetUiCopy.refreshFailed)),
      );
    } finally {
      if (mounted) {
        setState(() => _refreshingData = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final routeBackground = Theme.of(context).brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;
    final filteredCatalog = _selectedCategory == _WidgetCategory.all
        ? _widgetCatalog
        : _widgetCatalog
              .where((item) => item.category == _selectedCategory)
              .toList();

    return Scaffold(
      backgroundColor: routeBackground,
      appBar: AppBar(
        title: Text(WidgetUiCopy.screenTitle),
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
        backgroundColor: routeBackground.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
        actions: [
          if (PlatformInfo.isAndroid || PlatformInfo.isIOS)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: WidgetUiCopy.refreshTooltip,
              onPressed: _refreshingData ? null : _refreshWidgetData,
            ),
        ],
      ),
      body: AppSecondaryControlTheme(
        child: WebTarget.isDesktopWebBuild
            ? const _DesktopWebWidgetFallback()
            : ListView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                children: [
                  AppSurfaceCard(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: Colors.teal.withValues(alpha: 0.14),
                          child: const Icon(
                            Icons.widgets_outlined,
                            color: Colors.teal,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            WidgetUiCopy.previewHeaderTitle,
                            style: appSecondaryMenuItemTextStyle(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _WidgetDisplayModePanel(
                    value: _displayMode,
                    enabled: !_isUpdatingDisplayMode,
                    onChanged: _isUpdatingDisplayMode ? null : _setDisplayMode,
                  ),
                  const SizedBox(height: 12),
                  _WidgetPinSupportBanner(
                    result: _pinSupport,
                    checking: _checkingPinSupport,
                    canOpenSettings: _canOpenWidgetSettings,
                    onRefresh: _loadPinSupport,
                    onOpenSettings: _openWidgetSettings,
                  ),
                  const SizedBox(height: 12),
                  _WidgetCategoryFilter(
                    selected: _selectedCategory,
                    onSelected: (category) {
                      setState(() => _selectedCategory = category);
                    },
                  ),
                  for (final item in filteredCatalog) ...[
                    const SizedBox(height: 16),
                    _WidgetCatalogTile(
                      icon: item.icon,
                      title: item.title,
                      subtitle: item.subtitle,
                      color: item.color,
                    ),
                    const SizedBox(height: 10),
                    item.previewBuilder(_displayMode),
                    const SizedBox(height: 8),
                    _AddWidgetButton(
                      key: ValueKey(item.kind),
                      pinSupport: _pinSupport,
                      checkingPinSupport: _checkingPinSupport,
                      kind: item.kind,
                      displayMode: _displayMode,
                      canOpenWidgetSettings: _canOpenWidgetSettings,
                      onPinSupportChanged: _setPinSupport,
                    ),
                  ],
                  const SizedBox(height: 16),
                  AppInfoBanner(
                    icon: Icons.touch_app_outlined,
                    color: Colors.teal,
                    title: WidgetUiCopy.widgetTipsBannerTitle,
                    message: WidgetUiCopy.widgetTipsBannerMessage,
                  ),
                ],
              ),
      ),
    );
  }
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
          color: Colors.indigo,
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
            style: appSecondaryFilledButtonStyle(context),
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
        final segmented = SegmentedButton<_WidgetCategory>(
          segments: [
            for (final cat in _WidgetCategory.values)
              ButtonSegment<_WidgetCategory>(
                value: cat,
                label: Text(
                  cat.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          selected: {selected},
          showSelectedIcon: false,
          onSelectionChanged: (next) => onSelected(next.single),
        );
        if (constraints.maxWidth >= 320) {
          return SizedBox(width: double.infinity, child: segmented);
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: segmented,
          ),
        );
      },
    );
  }
}

class _WidgetPinSupportBanner extends StatelessWidget {
  final AndroidWidgetPinResult? result;
  final bool checking;
  final bool canOpenSettings;
  final VoidCallback onRefresh;
  final VoidCallback onOpenSettings;

  const _WidgetPinSupportBanner({
    required this.result,
    required this.checking,
    required this.canOpenSettings,
    required this.onRefresh,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final support = result;
    final supported = support == AndroidWidgetPinResult.requested;
    final blocked =
        support == AndroidWidgetPinResult.unsupportedLauncher ||
        support == AndroidWidgetPinResult.unsupportedPlatform ||
        support == AndroidWidgetPinResult.unavailable;
    final color = checking
        ? Colors.blueGrey
        : supported
        ? Colors.teal
        : blocked
        ? Colors.orange
        : Colors.blueGrey;
    final title = checking
        ? WidgetUiCopy.pinSupportCheckingTitle
        : supported
        ? WidgetUiCopy.pinSupportSupportedTitle
        : WidgetUiCopy.pinSupportResultTitle(support);
    final message = checking
        ? WidgetUiCopy.pinSupportCheckingMessage
        : supported
        ? WidgetUiCopy.pinSupportSupportedMessage
        : WidgetUiCopy.pinSupportResultMessage(support);
    final cs = Theme.of(context).colorScheme;
    final surfaceStyle = appSurfaceStyleOf(context);
    final iconRadius = surfaceStyle?.smallTileRadius ?? 10.0;
    return AppSurfaceCard(
      padding: const EdgeInsets.all(12),
      color: color.withValues(alpha: 0.08),
      border: Border.all(color: color.withValues(alpha: 0.12), width: 0.45),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 360;
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
              if (canOpenSettings)
                TextButton.icon(
                  onPressed: checking ? null : onOpenSettings,
                  icon: const Icon(Icons.settings_outlined, size: 16),
                  label: Text(WidgetUiCopy.actionAppSettings),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    minimumSize: const Size(44, 36),
                    textStyle: appSecondaryControlTextStyle(context),
                  ),
                ),
              TextButton.icon(
                onPressed: checking ? null : onRefresh,
                icon: const Icon(Icons.refresh, size: 16),
                label: Text(WidgetUiCopy.actionRecheck),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  minimumSize: const Size(44, 36),
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
}

class _WidgetDisplayModePanel extends StatelessWidget {
  final WidgetDisplayMode value;
  final bool enabled;
  final ValueChanged<WidgetDisplayMode>? onChanged;

  const _WidgetDisplayModePanel({
    required this.value,
    this.enabled = true,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
              final segmented = SegmentedButton<WidgetDisplayMode>(
                segments: [
                  for (final mode in WidgetDisplayMode.values)
                    ButtonSegment(
                      value: mode,
                      label: Text(
                        '${mode.label} ${mode.launcherRequestLabel}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                selected: {value},
                showSelectedIcon: false,
                onSelectionChanged: enabled && onChanged != null
                    ? (next) => onChanged!(next.single)
                    : null,
              );
              if (constraints.maxWidth >= 340) {
                return SizedBox(width: double.infinity, child: segmented);
              }
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: segmented,
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Text(
            value.description,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.normal,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _AddWidgetButton extends StatefulWidget {
  final DuoyiWidgetKind kind;
  final WidgetDisplayMode displayMode;
  final AndroidWidgetPinResult? pinSupport;
  final bool checkingPinSupport;
  final bool canOpenWidgetSettings;
  final ValueChanged<AndroidWidgetPinResult> onPinSupportChanged;

  const _AddWidgetButton({
    super.key,
    required this.kind,
    required this.displayMode,
    required this.pinSupport,
    required this.checkingPinSupport,
    required this.canOpenWidgetSettings,
    required this.onPinSupportChanged,
  });

  @override
  State<_AddWidgetButton> createState() => _AddWidgetButtonState();
}

class _AddWidgetButtonState extends State<_AddWidgetButton> {
  bool _requesting = false;

  @override
  Widget build(BuildContext context) {
    final support = widget.pinSupport;
    final disabledByPlatform =
        !widget.checkingPinSupport &&
        support != null &&
        support != AndroidWidgetPinResult.requested;
    final label = widget.checkingPinSupport
        ? WidgetUiCopy.checkingDesktopSupport
        : disabledByPlatform
        ? WidgetUiCopy.pinDisabledAction(support)
        : _requesting
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
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: FilledButton.icon(
              onPressed: _requesting || widget.checkingPinSupport
                  ? null
                  : disabledByPlatform
                  ? () => _showPinWidgetHelp(context, support)
                  : () => _request(context),
              style: appSecondaryFilledButtonStyle(context).copyWith(
                minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
              ),
              icon: _requesting
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      disabledByPlatform
                          ? Icons.help_outline
                          : Icons.add_to_home_screen_outlined,
                    ),
              label: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _request(BuildContext context) async {
    if (_requesting) return;
    final requestedKind = widget.kind;
    final requestedMode = widget.displayMode;
    setState(() => _requesting = true);
    try {
      final support = await AndroidWidgetManager.checkPinSupport();
      if (!context.mounted) return;
      widget.onPinSupportChanged(support);
      if (support != AndroidWidgetPinResult.requested) {
        await AndroidWidgetManager.refreshAllWidgets();
        if (!context.mounted) return;
        await _showPinWidgetHelp(context, support);
        return;
      }
      final request = await AndroidWidgetManager.requestPinWidgetDetailed(
        requestedKind,
        style: requestedMode.androidStyle,
      );
      if (!context.mounted) return;
      if (request.result == AndroidWidgetPinResult.requested) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              WidgetUiCopy.pinInitiatedSnackBar(requestedMode.label),
            ),
          ),
        );
        final requestId = request.requestId;
        if (requestId == null || requestId.isEmpty) return;
        final confirmation = await AndroidWidgetManager.waitForPinResult(
          requestId,
        );
        if (!context.mounted) return;
        if (confirmation.isSuccess) {
          await AndroidWidgetManager.refreshAllWidgets();
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                WidgetUiCopy.pinSuccessSnackBar(requestedMode.label),
              ),
            ),
          );
          await AndroidWidgetManager.clearPinResult(requestId);
          return;
        }
        await AndroidWidgetManager.refreshAllWidgets();
        if (!context.mounted) return;
        await _showPinWidgetConfirmationFailureHelp(context, confirmation);
        return;
      }
      await AndroidWidgetManager.refreshAllWidgets();
      if (!context.mounted) return;
      await _showPinWidgetHelp(context, request.result);
    } finally {
      if (mounted) {
        setState(() => _requesting = false);
      }
    }
  }

  Future<void> _showPinWidgetHelp(
    BuildContext context,
    AndroidWidgetPinResult result,
  ) async {
    // 静态校验兼容：系统小组件列表 权限 确认
    final message = switch (result) {
      AndroidWidgetPinResult.unsupportedLauncher => WidgetUiCopy.pinHelpMessage(
        AndroidWidgetPinResult.unsupportedLauncher,
      ),
      AndroidWidgetPinResult.permissionDenied => WidgetUiCopy.pinHelpMessage(
        AndroidWidgetPinResult.permissionDenied,
      ),
      AndroidWidgetPinResult.confirmationBlocked => WidgetUiCopy.pinHelpMessage(
        AndroidWidgetPinResult.confirmationBlocked,
      ),
      _ => WidgetUiCopy.pinHelpMessage(result),
    };
    await showDialog<void>(
      context: context,
      builder: (ctx) => AppDialog(
        title: Text(WidgetUiCopy.addDialogTitle),
        content: Text(message),
        actions: [
          if (widget.canOpenWidgetSettings)
            TextButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                await _openWidgetSettings(context);
              },
              icon: const Icon(Icons.settings_outlined),
              label: Text(WidgetUiCopy.actionOpenPermissions), // 打开权限设置
            ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            style: appSecondaryFilledButtonStyle(ctx),
            child: Text(WidgetUiCopy.actionGotIt),
          ),
        ],
      ),
    );
  }

  Future<void> _showPinWidgetConfirmationFailureHelp(
    BuildContext context,
    AndroidWidgetPinConfirmation confirmation,
  ) async {
    final (title, message) = switch (confirmation.status) {
      AndroidWidgetPinFinalStatus.invalidWidgetId =>
        WidgetUiCopy.pinConfirmationFailure(
          AndroidWidgetPinFinalStatus.invalidWidgetId,
        ),
      AndroidWidgetPinFinalStatus.timeout =>
        WidgetUiCopy.pinConfirmationFailure(
          AndroidWidgetPinFinalStatus.timeout,
        ),
      AndroidWidgetPinFinalStatus.unavailable =>
        WidgetUiCopy.pinConfirmationFailure(
          AndroidWidgetPinFinalStatus.unavailable,
        ),
      AndroidWidgetPinFinalStatus.success =>
        WidgetUiCopy.pinConfirmationFailure(
          AndroidWidgetPinFinalStatus.success,
        ),
    };
    await showDialog<void>(
      context: context,
      builder: (ctx) => AppDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          if (widget.canOpenWidgetSettings)
            TextButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                await _openWidgetSettings(context);
              },
              icon: const Icon(Icons.settings_outlined),
              label: Text(WidgetUiCopy.actionOpenPermissions), // 打开权限设置
            ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            style: appSecondaryFilledButtonStyle(ctx),
            child: Text(WidgetUiCopy.actionGotIt),
          ),
        ],
      ),
    );
  }

  Future<void> _openWidgetSettings(BuildContext context) async {
    final opened = await AndroidWidgetManager.openWidgetSettings();
    if (!context.mounted) return;
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: _widgetFeedback(() => WidgetUiCopy.cannotOpenSettings),
        ),
      );
    }
  }
}

class WidgetPreviewCard extends StatelessWidget {
  final WidgetPreviewKind kind;
  final WidgetDisplayMode displayMode;

  const WidgetPreviewCard.todo({
    super.key,
    this.displayMode = WidgetDisplayMode.standard,
  }) : kind = WidgetPreviewKind.todo;
  const WidgetPreviewCard.focus({
    super.key,
    this.displayMode = WidgetDisplayMode.standard,
  }) : kind = WidgetPreviewKind.focus;
  const WidgetPreviewCard.habit({
    super.key,
    this.displayMode = WidgetDisplayMode.standard,
  }) : kind = WidgetPreviewKind.habit;
  const WidgetPreviewCard.calendar({
    super.key,
    this.displayMode = WidgetDisplayMode.standard,
  }) : kind = WidgetPreviewKind.calendar;
  const WidgetPreviewCard.schedule({
    super.key,
    this.displayMode = WidgetDisplayMode.standard,
  }) : kind = WidgetPreviewKind.schedule;
  const WidgetPreviewCard.goal({
    super.key,
    this.displayMode = WidgetDisplayMode.standard,
  }) : kind = WidgetPreviewKind.goal;
  const WidgetPreviewCard.course({
    super.key,
    this.displayMode = WidgetDisplayMode.standard,
  }) : kind = WidgetPreviewKind.course;
  const WidgetPreviewCard.note({
    super.key,
    this.displayMode = WidgetDisplayMode.standard,
  }) : kind = WidgetPreviewKind.note;
  const WidgetPreviewCard.anniversary({
    super.key,
    this.displayMode = WidgetDisplayMode.standard,
  }) : kind = WidgetPreviewKind.anniversary;
  const WidgetPreviewCard.diary({
    super.key,
    this.displayMode = WidgetDisplayMode.standard,
  }) : kind = WidgetPreviewKind.diary;

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
    final cs = Theme.of(context).colorScheme;
    final surfaceStyle = appSurfaceStyleOf(context);
    ThemeProvider? themeProvider;
    try {
      themeProvider = context.watch<ThemeProvider>();
    } catch (_) {
      themeProvider = null;
    }
    final cardSkin = themeProvider?.activeCardSkin;
    final usesCardSkin =
        cardSkin != null && cardSkin.id != ThemeProvider.defaultCardSkinId;
    final accent = switch (kind) {
      WidgetPreviewKind.todo => Colors.blue,
      WidgetPreviewKind.focus => Colors.redAccent,
      WidgetPreviewKind.habit => Colors.green,
      WidgetPreviewKind.calendar => Colors.indigo,
      WidgetPreviewKind.schedule => Colors.cyan,
      WidgetPreviewKind.goal => Colors.orange,
      WidgetPreviewKind.course => Colors.orange,
      WidgetPreviewKind.note => Colors.purple,
      WidgetPreviewKind.anniversary => Colors.pink,
      WidgetPreviewKind.diary => Colors.teal,
    };
    final title = WidgetUiCopy.previewTitle(kind);
    final skin = cardSkin;
    final widgetBrand = themeProvider?.activeWidgetBackgroundBrand;
    final previewBackgroundAsset = widgetBrand?.backgroundAsset;
    final imageBacked = previewBackgroundAsset != null;
    final brightness = Theme.of(context).brightness;
    final backgroundStart = usesCardSkin && skin != null
        ? skin.colors.first
        : cs.primary;
    final backgroundEnd = usesCardSkin && skin != null
        ? skin.colors.last
        : cs.surface;
    final previewBackground = Color.alphaBlend(
      backgroundStart.withValues(
        alpha: Theme.of(context).brightness == Brightness.dark ? 0.22 : 0.12,
      ),
      cs.surface,
    );
    final previewGradient = LinearGradient(
      colors: [
        previewBackground,
        Color.alphaBlend(
          backgroundEnd.withValues(
            alpha: usesCardSkin
                ? (Theme.of(context).brightness == Brightness.dark
                      ? 0.20
                      : 0.14)
                : 0.05,
          ),
          cs.surface,
        ),
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
    final imageOverlay = LinearGradient(
      colors: brightness == Brightness.dark
          ? [
              Colors.black.withValues(alpha: 0.34),
              cs.surface.withValues(alpha: 0.46),
            ]
          : [
              (widgetBrand?.backgroundOverlay ?? cs.surface).withValues(
                alpha: 0.42,
              ),
              cs.surface.withValues(alpha: 0.58),
            ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
    final previewCardRadius = surfaceStyle?.cardRadius ?? 16.0;
    return Semantics(
      label: '$title ${displayMode.previewCellLabel}',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final available = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : displayMode.previewMaxWidth;
          final width = available < displayMode.previewMaxWidth
              ? available
              : displayMode.previewMaxWidth;
          return Align(
            alignment: Alignment.center,
            child: SizedBox(
              width: width,
              child: AspectRatio(
                aspectRatio:
                    displayMode.previewAspectRatio /
                    (MediaQuery.textScalerOf(context).scale(12) / 12).clamp(
                      1.0,
                      2.0,
                    ),
                child: Container(
                  clipBehavior: Clip.hardEdge,
                  decoration: BoxDecoration(
                    color: imageBacked ? cs.surface : previewBackground,
                    gradient: imageBacked ? null : previewGradient,
                    borderRadius: BorderRadius.circular(previewCardRadius),
                    border: Border.all(
                      color: cs.primary.withValues(alpha: 0.16),
                      width: 0.45,
                    ),
                  ),
                  child: Stack(
                    children: [
                      if (imageBacked)
                        Positioned.fill(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final dpr = MediaQuery.devicePixelRatioOf(
                                context,
                              ).clamp(1.0, 3.0);
                              final cacheWidth = (constraints.maxWidth * dpr)
                                  .ceil()
                                  .clamp(1, 1600);
                              final cacheHeight = (constraints.maxHeight * dpr)
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
                                        gradient: previewGradient,
                                      ),
                                    ),
                              );
                            },
                          ),
                        ),
                      if (imageBacked)
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(gradient: imageOverlay),
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
                                    WidgetUiCopy.previewSampleBadge(title),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
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
                                    WidgetUiCopy.sampleHeaderDate(
                                      displayMode.previewCellLabel,
                                    ),
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
                            if (displayMode != WidgetDisplayMode.compact) ...[
                              const SizedBox(height: 10),
                              _WidgetPreviewNav(
                                selectedIndex: switch (kind) {
                                  WidgetPreviewKind.todo => 0,
                                  WidgetPreviewKind.focus => 3,
                                  WidgetPreviewKind.habit => 1,
                                  WidgetPreviewKind.calendar => 2,
                                  WidgetPreviewKind.schedule => 2,
                                  WidgetPreviewKind.goal => 2,
                                  WidgetPreviewKind.course => 2,
                                  WidgetPreviewKind.note => 2,
                                  WidgetPreviewKind.anniversary => 2,
                                  WidgetPreviewKind.diary => 2,
                                },
                                accent: accent,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
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

  const _WidgetPreviewContentFrame({required this.mode, required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : mode.previewMaxWidth;
        return ClipRect(
          child: Align(
            alignment: Alignment.topLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: _WidgetPreviewDensity(mode: mode, child: child),
              ),
            ),
          ),
        );
      },
    );
  }
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

class _WidgetPreviewTodoBody extends StatelessWidget {
  const _WidgetPreviewTodoBody();

  @override
  Widget build(BuildContext context) {
    final maxLines = _WidgetPreviewDensityScope.maxLinesOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _WidgetPreviewTodoRow(text: WidgetUiCopy.todoItem1),
        if (maxLines >= 2) ...[
          const SizedBox(height: 7),
          _WidgetPreviewTodoRow(text: WidgetUiCopy.todoItem2),
        ],
        if (maxLines >= 3) ...[
          const SizedBox(height: 7),
          _WidgetPreviewTodoRow(text: WidgetUiCopy.todoItem3),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _WidgetPreviewLine(
                  icon: Icons.checklist_rtl_outlined,
                  text: WidgetUiCopy.todoSummaryCount,
                ),
              ),
              _WidgetPreviewQuickAdd(label: WidgetUiCopy.todoQuickAdd),
            ],
          ),
        ],
      ],
    );
  }
}

class _WidgetPreviewFocusBody extends StatelessWidget {
  const _WidgetPreviewFocusBody();

  @override
  Widget build(BuildContext context) {
    final maxLines = _WidgetPreviewDensityScope.maxLinesOf(context);
    final surfaceStyle = appSurfaceStyleOf(context);
    final buttonRadius = surfaceStyle?.smallTileRadius ?? 8.0;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _WidgetPreviewMetric(
                value: '2',
                label: WidgetUiCopy.focusMetricSessions,
                color: Colors.redAccent,
              ),
            ),
            Expanded(
              child: _WidgetPreviewMetric(
                value: '50',
                label: WidgetUiCopy.focusMetricDuration,
                color: Colors.redAccent,
              ),
            ),
            Expanded(
              child: _WidgetPreviewMetric(
                value: '25',
                label: WidgetUiCopy.focusMetricNext,
                color: Colors.redAccent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Container(
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.circular(buttonRadius),
                ),
                child: Text(
                  WidgetUiCopy.focusStartButton,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ),
            ),
          ],
        ),
        if (maxLines >= 2) ...[
          const SizedBox(height: 8),
          _WidgetPreviewLine(
            icon: Icons.timer_outlined,
            text: WidgetUiCopy.focusLine1,
          ),
        ],
        if (maxLines >= 3) ...[
          _WidgetPreviewLine(
            icon: Icons.play_circle_outline,
            text: WidgetUiCopy.focusLine2,
          ),
          _WidgetPreviewLine(
            icon: Icons.touch_app_outlined,
            text: WidgetUiCopy.focusLine3,
          ),
        ],
      ],
    );
  }
}

class _WidgetPreviewHabitBody extends StatelessWidget {
  const _WidgetPreviewHabitBody();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxLines = _WidgetPreviewDensityScope.maxLinesOf(context);
    final surfaceStyle = appSurfaceStyleOf(context);
    final chipRadius = surfaceStyle?.smallTileRadius ?? 8.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                WidgetUiCopy.habitTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ),
            const Text(
              '80%',
              style: TextStyle(
                fontSize: 14,
                color: Colors.green,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _WidgetPreviewLine(
          icon: Icons.self_improvement_outlined,
          text: WidgetUiCopy.habitLine1,
        ),
        if (maxLines >= 2) ...[
          const SizedBox(height: 4),
          _WidgetPreviewLine(
            icon: Icons.local_fire_department_outlined,
            text: WidgetUiCopy.habitLine2,
          ),
        ],
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Container(
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(chipRadius),
                  border: Border.all(
                    color: Colors.green.withValues(alpha: 0.28),
                    width: 0.45,
                  ),
                ),
                child: Text(
                  WidgetUiCopy.habitCheckInButton,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.green,
                    fontSize: 11,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _WidgetPreviewCalendarBody extends StatelessWidget {
  const _WidgetPreviewCalendarBody();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxLines = _WidgetPreviewDensityScope.maxLinesOf(context);
    const currentWeekIndex = 2;
    final visibleWeeks = switch (maxLines) {
      1 => [currentWeekIndex],
      2 => [
        currentWeekIndex - 1,
        currentWeekIndex,
        currentWeekIndex + 1,
        currentWeekIndex + 2,
      ],
      _ => [0, 1, 2, 3, 4, 5],
    };
    final weekLabels = WidgetUiCopy.calendarWeekLabels;
    const monthWeeks = <List<int?>>[
      [null, null, null, null, 1, 2, 3],
      [4, 5, 6, 7, 8, 9, 10],
      [11, 12, 13, 14, 15, 16, 17],
      [18, 19, 20, 21, 22, 23, 24],
      [25, 26, 27, 28, 29, 30, 31],
      [null, null, null, null, null, null, null],
    ];
    final surfaceStyle = appSurfaceStyleOf(context);
    final chipRadius = surfaceStyle?.smallTileRadius ?? 8.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                WidgetUiCopy.calendarMonthHeader(2026, 5),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ),
            Container(
              height: 22,
              padding: const EdgeInsets.symmetric(horizontal: 9),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(chipRadius),
                border: Border.all(
                  color: Colors.blue.withValues(alpha: 0.28),
                  width: 0.45,
                ),
              ),
              child: Text(
                WidgetUiCopy.calendarToday,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.blue,
                  fontSize: 11,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        _WidgetPreviewCalendarGrid(
          weekLabels: weekLabels,
          weeks: [for (final index in visibleWeeks) monthWeeks[index]],
        ),
      ],
    );
  }
}

class _WidgetPreviewCalendarGrid extends StatelessWidget {
  final List<String> weekLabels;
  final List<List<int?>> weeks;

  const _WidgetPreviewCalendarGrid({
    required this.weekLabels,
    required this.weeks,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Row(
          children: [
            for (final label in weekLabels)
              Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: TextStyle(
                    fontSize: 10,
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (final week in weeks) ...[
          Row(
            children: [
              for (final day in week)
                Expanded(child: _WidgetPreviewCalendarCell(day: day)),
            ],
          ),
          const SizedBox(height: 3),
        ],
      ],
    );
  }
}

class _WidgetPreviewCalendarCell extends StatelessWidget {
  final int? day;

  const _WidgetPreviewCalendarCell({required this.day});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final surfaceStyle = appSurfaceStyleOf(context);
    final cellRadius = surfaceStyle?.smallTileRadius ?? 8.0;
    final isToday = day == 17;
    return Center(
      child: Container(
        width: 22,
        height: 20,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isToday ? Colors.blue : Colors.transparent,
          borderRadius: BorderRadius.circular(cellRadius),
        ),
        child: Text(
          day == null ? '' : '$day',
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: TextStyle(
            fontSize: 10,
            color: isToday ? Colors.white : cs.onSurface,
            fontWeight: FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _WidgetPreviewScheduleBody extends StatelessWidget {
  const _WidgetPreviewScheduleBody();

  @override
  Widget build(BuildContext context) {
    return _WidgetPreviewLineList(
      lines: [
        _WidgetPreviewLine(
          icon: Icons.notifications_active_outlined,
          text: WidgetUiCopy.scheduleItem1,
        ),
        _WidgetPreviewLine(
          icon: Icons.event_note_outlined,
          text: WidgetUiCopy.scheduleItem2,
        ),
        _WidgetPreviewLine(
          icon: Icons.event_available_outlined,
          text: WidgetUiCopy.scheduleItem3,
        ),
      ],
    );
  }
}

class _WidgetPreviewGoalBody extends StatelessWidget {
  const _WidgetPreviewGoalBody();

  @override
  Widget build(BuildContext context) {
    return _WidgetPreviewLineList(
      lines: [
        _WidgetPreviewLine(
          icon: Icons.flag_outlined,
          text: WidgetUiCopy.goalItem1, // 68%
        ),
        _WidgetPreviewLine(
          icon: Icons.trending_up_outlined,
          text: WidgetUiCopy.goalItem2,
        ),
        _WidgetPreviewLine(
          icon: Icons.check_circle_outline,
          text: WidgetUiCopy.goalItem3,
        ),
      ],
    );
  }
}

class _WidgetPreviewCourseBody extends StatelessWidget {
  const _WidgetPreviewCourseBody();

  @override
  Widget build(BuildContext context) {
    return _WidgetPreviewLineList(
      lines: [
        _WidgetPreviewLine(
          icon: Icons.school_outlined,
          text: WidgetUiCopy.courseItem1,
        ),
        _WidgetPreviewLine(
          icon: Icons.school_outlined,
          text: WidgetUiCopy.courseItem2,
        ),
        _WidgetPreviewLine(
          icon: Icons.event_note_outlined,
          text: WidgetUiCopy.courseItem3,
        ),
      ],
    );
  }
}

class _WidgetPreviewNoteBody extends StatelessWidget {
  const _WidgetPreviewNoteBody();

  @override
  Widget build(BuildContext context) {
    return _WidgetPreviewLineList(
      lines: [
        _WidgetPreviewLine(
          icon: Icons.edit_note_outlined,
          text: WidgetUiCopy.noteItem1,
        ),
        _WidgetPreviewLine(
          icon: Icons.lightbulb_outline,
          text: WidgetUiCopy.noteItem2,
        ),
        _WidgetPreviewLine(
          icon: Icons.menu_book_outlined,
          text: WidgetUiCopy.noteItem3,
        ),
      ],
    );
  }
}

class _WidgetPreviewAnniversaryBody extends StatelessWidget {
  const _WidgetPreviewAnniversaryBody();

  @override
  Widget build(BuildContext context) {
    return _WidgetPreviewLineList(
      lines: [
        _WidgetPreviewLine(
          icon: Icons.event_available_outlined,
          text: WidgetUiCopy.anniversaryItem1,
        ),
        _WidgetPreviewLine(
          icon: Icons.event_available_outlined,
          text: WidgetUiCopy.anniversaryItem2,
        ),
        _WidgetPreviewLine(
          icon: Icons.event_available_outlined,
          text: WidgetUiCopy.anniversaryItem3,
        ),
      ],
    );
  }
}

class _WidgetPreviewDiaryBody extends StatelessWidget {
  const _WidgetPreviewDiaryBody();

  @override
  Widget build(BuildContext context) {
    return _WidgetPreviewLineList(
      lines: [
        _WidgetPreviewLine(
          icon: Icons.book_outlined,
          text: WidgetUiCopy.diaryItem1,
        ),
        _WidgetPreviewLine(
          icon: Icons.book_outlined,
          text: WidgetUiCopy.diaryItem2,
        ),
        _WidgetPreviewLine(
          icon: Icons.book_outlined,
          text: WidgetUiCopy.diaryItem3,
        ),
      ],
    );
  }
}

class _WidgetPreviewLineList extends StatelessWidget {
  final List<Widget> lines;

  const _WidgetPreviewLineList({required this.lines});

  @override
  Widget build(BuildContext context) {
    final maxLines = _WidgetPreviewDensityScope.maxLinesOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final line in lines.take(maxLines)) line],
    );
  }
}

class _WidgetPreviewQuickAdd extends StatelessWidget {
  final String label;

  const _WidgetPreviewQuickAdd({required this.label});

  @override
  Widget build(BuildContext context) {
    final surfaceStyle = appSurfaceStyleOf(context);
    final chipRadius = surfaceStyle?.smallTileRadius ?? 8.0;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(chipRadius),
          border: Border.all(
            color: Colors.blue.withValues(alpha: 0.28),
            width: 0.45,
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.blue,
            fontSize: 11,
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 13, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WidgetPreviewTodoRow extends StatelessWidget {
  final String text;

  const _WidgetPreviewTodoRow({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final surfaceStyle = appSurfaceStyleOf(context);
    final boxRadius = surfaceStyle?.smallTileRadius ?? 8.0;
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(boxRadius),
            border: Border.all(
              color: Colors.blue.withValues(alpha: 0.28),
              width: 0.45,
            ),
          ),
          child: const Text(
            '○',
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: TextStyle(
              color: Colors.blue,
              fontSize: 13,
              fontWeight: FontWeight.normal,
            ),
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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

  const _WidgetPreviewMetric({
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.normal,
            color: color,
          ),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 10,
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.normal,
          ),
        ),
      ],
    );
  }
}

class _WidgetPreviewNav extends StatelessWidget {
  final int selectedIndex;
  final Color accent;

  const _WidgetPreviewNav({required this.selectedIndex, required this.accent});

  @override
  Widget build(BuildContext context) {
    final labels = WidgetUiCopy.previewNavLabels;
    final cs = Theme.of(context).colorScheme;
    final surfaceStyle = appSurfaceStyleOf(context);
    final navRadius = surfaceStyle?.smallTileRadius ?? 8.0;
    return Container(
      key: const ValueKey('widget_preview_navigation'),
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 30),
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(navRadius),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.18),
          width: 0.45,
        ),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceEvenly,
        runSpacing: 4,
        children: [
          for (var i = 0; i < labels.length; i++)
            Text(
              labels[i],
              textAlign: TextAlign.center,
              softWrap: false,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.normal,
                color: i == selectedIndex ? accent : cs.onSurfaceVariant,
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
        CircleAvatar(
          radius: 18,
          backgroundColor: color.withValues(alpha: 0.14),
          child: Icon(icon, size: 20, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.normal,
                  color: cs.onSurface,
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
