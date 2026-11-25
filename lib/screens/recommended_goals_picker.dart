/// 推荐目标选择器（Recommended Goals Picker）。
///
/// - 顶部：水平可滚动的类别分段（5 个主类别：推荐/健康/学习/运动/情感）。
///   不使用 `SegmentedButton`，因为分段 ≤5 且 UI 上希望允许未来扩类；
///   改用水平 `ListView` 渲染 `ChoiceChip`，既能滑动又能高亮选中。
/// - 中部：按当前选中类别筛选 [RecommendedGoalsLibrary.byCategory] 的条目，
///   以卡片列表形式展示（标题 / 描述 / 元信息徽章 / 添加按钮）。
/// - 点击卡片或加号按钮 → 把模板实例化后写入 [GoalProvider]，并弹
///   SnackBar 提示"已添加到目标列表"。
///
/// 关于 `recommend` 类别的约定：当用户选中 `GoalCategory.recommend` 时，
/// 本页面只展示 `byCategory(recommend)` 对应的 5 条通用推荐条目，**不**
/// 合并展示其它 4 类的内容。这和 `RecommendedGoalsLibrary` 的分类语义保持
/// 一致，避免重复呈现。
///
/// 关于写入 Provider 的策略：本页调用 `GoalProvider.applyRecommended(r)` 把
/// 模板实例化后写入本地；Provider 返回新创建的 [GoalItem]，SnackBar 的
/// "查看"动作用它作为 `Navigator.pop` 的返回值，供上游辨认已创建的目标；当前 GoalScreen 返回目标列表。
///
/// 对应 Requirements: 1.3, 1.4。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../core/account_preference_writes.dart';
import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../core/recommended_goals_ui_copy.dart';
import '../core/goal_icons.dart';
import '../core/recommended_goals.dart';
import '../models/goal.dart';
import '../providers/goal_provider.dart';
import '../providers/app_lock_provider.dart';
import '../services/account_local_data_cleaner.dart';
import '../services/app_access_route_gate.dart';
import '../services/app_update_service.dart';
import '../services/goal_editor_origin.dart';
import '../widgets/app_date_picker.dart';
import '../widgets/brand_background.dart';
import '../widgets/empty_state.dart';
import '../widgets/surface_components.dart';

/// 顶部 5 个主类别（和 [RecommendedGoalsLibrary] 对齐，排除 `custom`）。
const List<GoalCategory> _pickerCategories = <GoalCategory>[
  GoalCategory.recommend,
  GoalCategory.health,
  GoalCategory.study,
  GoalCategory.sport,
  GoalCategory.emotion,
];

/// 推荐目标选择器页面。
class RecommendedGoalsPicker extends StatefulWidget
    implements LocaleStatePreservingRoute {
  /// 进入页面时默认选中的类别，默认为 [GoalCategory.recommend]。
  final GoalCategory initialCategory;

  const RecommendedGoalsPicker({
    super.key,
    this.initialCategory = GoalCategory.recommend,
  });

  @override
  State<RecommendedGoalsPicker> createState() => _RecommendedGoalsPickerState();
}

class _RecommendedGoalsPickerState extends State<RecommendedGoalsPicker> {
  late GoalCategory _selected;
  String? _pendingId;
  GoalEditorOrigin? _pageOrigin;
  AppLockProvider? _pageLock;
  AppUpdateService? _pageUpdate;
  int _renderRevision = 0;
  bool _rebuildScheduled = false;
  bool _pageExpired = false;
  final _pageNotifiers = <ChangeNotifier>[];
  final _pageGates = <AppAccessRouteGate>[];
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  _RecommendationOperation? _operation;

  @override
  void initState() {
    super.initState();
    // 如果传入了 `custom`（理论上不会），回退到 recommend。
    _selected = _pickerCategories.contains(widget.initialCategory)
        ? widget.initialCategory
        : GoalCategory.recommend;
  }

  void _select(GoalCategory c) {
    if (_selected == c) return;
    setState(() => _selected = c);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_pageOrigin != null) {
      _sourceChanged();
      return;
    }
    _pageOrigin = GoalEditorOrigin.capture(context);
    _pageLock = context.read<AppLockProvider?>();
    _pageUpdate = context.read<AppUpdateService?>();
    for (final notifier in [
      _pageOrigin!.provider,
      _pageOrigin!.auth,
      _pageLock,
      _pageUpdate,
    ]) {
      if (notifier != null) {
        _pageNotifiers.add(notifier);
        notifier.addListener(_sourceChanged);
      }
    }
    AccountLocalDataCleaner.accountDataGenerationListenable.addListener(
      _sourceChanged,
    );
    for (final observer in Navigator.of(context).widget.observers) {
      if (observer is AppAccessRouteGate) {
        _pageGates.add(observer);
        observer.routeRevision.addListener(_sourceChanged);
      }
    }
  }

  void _sourceChanged() {
    // Invalidate callbacks synchronously, including leave/return in one frame.
    _renderRevision++;
    if (_rebuildScheduled) return;
    _rebuildScheduled = true;
    void rebuild() {
      _rebuildScheduled = false;
      if (!mounted) return;
      if (_pageOrigin?.isCurrent(context) != true ||
          (_operation != null && !_operation!.isCurrent())) {
        _messenger.currentState?.clearSnackBars();
      }
      setState(() {});
    }

    scheduleMicrotask(() {
      if (!mounted) return;
      if (SchedulerBinding.instance.schedulerPhase ==
          SchedulerPhase.persistentCallbacks) {
        WidgetsBinding.instance.addPostFrameCallback((_) => rebuild());
      } else {
        rebuild();
      }
    });
  }

  bool _canUse(int revision) =>
      mounted &&
      revision == _renderRevision &&
      _pageSourceCurrent() &&
      _pageOrigin?.isCurrent(context) == true;

  bool _pageSourceCurrent() =>
      mounted &&
      !_pageExpired &&
      identical(context.read<AppLockProvider?>(), _pageLock) &&
      identical(context.read<AppUpdateService?>(), _pageUpdate) &&
      _pageOrigin?.isCurrent(context, checkRoute: false, checkAccess: false) ==
          true;

  @override
  void dispose() {
    AccountLocalDataCleaner.accountDataGenerationListenable.removeListener(
      _sourceChanged,
    );
    for (final notifier in _pageNotifiers) {
      notifier.removeListener(_sourceChanged);
    }
    for (final gate in _pageGates) {
      gate.routeRevision.removeListener(_sourceChanged);
    }
    _operation?.dispose();
    super.dispose();
  }

  Future<void> _apply(RecommendedGoal recommendation, int revision) async {
    if (_pendingId != null || !_canUse(revision)) return;
    final origin = _pageOrigin!;
    _operation?.dispose();
    final operation = _RecommendationOperation(context, origin);
    _operation = operation;
    if (!operation.isCurrent()) return;
    setState(() => _pendingId = recommendation.id);
    try {
      DateTime? targetDate;
      if (recommendation.requiresTargetDate) {
        final now = DateTime.now();
        final initialDate = DateTime(now.year, now.month, now.day);
        final pickerRoute = AppDatePicker.buildRoute(
          context,
          initialDate: initialDate,
          firstDate: DateTime(1900),
          lastDate: DateTime(2099, 12, 31),
          titleBuilder: () => recommendation.localizedTitle,
          subtitleBuilder: () => RecommendedGoalsUiCopy.selectTargetDate,
        );
        operation.own(pickerRoute);
        AppDatePickerResult? result;
        try {
          final pending = Navigator.of(context).push(pickerRoute);
          operation.listenForCover();
          result = await pending;
          await pickerRoute.completed;
        } finally {
          operation.release(pickerRoute);
        }
        if (!mounted || !operation.isCurrent() || result == null) {
          return;
        }
        targetDate = result.date;
      }
      final goal = await origin.provider.applyRecommended(
        recommendation,
        targetDate: targetDate,
        canWrite: operation.isCurrent,
      );
      if (!mounted || !operation.isCurrent()) return;
      _messenger.currentState!
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: ValueListenableBuilder<AppLocale>(
              valueListenable: I18n.localeListenable,
              builder: (context, _, _) => Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: DesignTokens.spaceSm,
                children: [
                  Text(RecommendedGoalsUiCopy.saved),
                  TextButton(
                    key: const ValueKey('recommended-goal-view'),
                    onPressed: () {
                      if (!mounted || !operation.isCurrent()) return;
                      Navigator.of(this.context).pop(goal);
                    },
                    child: Text(RecommendedGoalsUiCopy.view),
                  ),
                ],
              ),
            ),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
            shape: const RoundedRectangleBorder(
              borderRadius: DesignTokens.borderRadiusSm,
            ),
          ),
        );
    } on AccountPreferenceWriteCanceled {
      // A departed account or route no longer owns this request.
    } catch (_) {
      if (!mounted || !operation.isCurrent()) return;
      _messenger.currentState!
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: ValueListenableBuilder<AppLocale>(
              valueListenable: I18n.localeListenable,
              builder: (context, _, _) =>
                  Text(RecommendedGoalsUiCopy.saveFailed),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } finally {
      if (mounted && identical(_operation, operation)) {
        setState(() => _pendingId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppLocale>(
    valueListenable: I18n.localeListenable,
    builder: (context, _, _) => _buildLocalized(context),
  );

  Widget _buildLocalized(BuildContext context) {
    context.watch<GoalProvider>();
    context.watch<AppLockProvider?>();
    context.watch<AppUpdateService?>();
    if (!_pageExpired && !_pageSourceCurrent()) {
      _pageExpired = true;
      _sourceChanged();
    }
    final revision = _renderRevision;
    final canUse = _canUse(revision);
    final items = RecommendedGoalsLibrary.byCategory(_selected);
    final cs = Theme.of(context).colorScheme;
    final routeBackground = Theme.of(context).brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;
    final hasBrandSurface =
        context.findAncestorWidgetOfExactType<BrandRouteSurface>() != null;
    return ScaffoldMessenger(
      key: _messenger,
      child: Scaffold(
        backgroundColor:
            hasBrandSurface ? Colors.transparent : routeBackground,
        appBar: AppBar(
          title: Text(RecommendedGoalsUiCopy.title),
          titleTextStyle: appSecondaryRouteTitleTextStyle(context),
          backgroundColor: routeBackground.withValues(alpha: 0.96),
          surfaceTintColor: Colors.transparent,
        ),
        body: AppSecondaryControlTheme(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_pageSourceCurrent())
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: DesignTokens.spaceLg,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(RecommendedGoalsUiCopy.expired),
                      TextButton(
                        onPressed: () {
                          if (!mounted ||
                              revision != _renderRevision ||
                              !identical(
                                ModalRoute.of(context),
                                _pageOrigin?.route,
                              ) ||
                              _pageOrigin?.route?.isCurrent != true ||
                              context.read<AppLockProvider?>()?.isLocked ==
                                  true ||
                              context.read<AppUpdateService?>()?.mustUpdate ==
                                  true) {
                            return;
                          }
                          Navigator.of(context).maybePop();
                        },
                        child: Text(RecommendedGoalsUiCopy.back),
                      ),
                    ],
                  ),
                ),
              _CategoryChipRow(
                categories: _pickerCategories,
                selected: _selected,
                onSelect: (category) {
                  if (_canUse(revision)) _select(category);
                },
              ),
              const SizedBox(height: DesignTokens.spaceXs),
              Expanded(
                child: items.isEmpty
                    ? _EmptyCategoryPlaceholder(category: _selected)
                    : ListView.separated(
                        key: PageStorageKey(
                          'recommended-goal-list-${_selected.name}',
                        ),
                        padding: const EdgeInsets.fromLTRB(
                          DesignTokens.spaceLg,
                          DesignTokens.spaceSm,
                          DesignTokens.spaceLg,
                          DesignTokens.spaceXxl,
                        ),
                        itemCount: items.length,
                        separatorBuilder: (context, _) =>
                            const SizedBox(height: DesignTokens.spaceMd),
                        itemBuilder: (_, i) => _RecommendedGoalCard(
                          goal: items[i],
                          pending: _pendingId == items[i].id,
                          onApply: _pendingId == null && canUse
                              ? () => _apply(items[i], revision)
                              : null,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 类别分段随字体高度自然展开，超出宽度时水平滚动。
class _CategoryChipRow extends StatelessWidget {
  final List<GoalCategory> categories;
  final GoalCategory selected;
  final ValueChanged<GoalCategory> onSelect;

  const _CategoryChipRow({
    required this.categories,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spaceLg,
        vertical: DesignTokens.spaceSm,
      ),
      child: Row(
        children: [
          for (final category in categories) ...[
            if (category != categories.first)
              const SizedBox(width: DesignTokens.spaceSm),
            ChoiceChip(
              key: ValueKey('recommended-category-${category.name}'),
              label: Text(RecommendedGoalsUiCopy.category(category)),
              selected: selected == category,
              onSelected: (_) => onSelect(category),
            ),
          ],
        ],
      ),
    );
  }
}

/// 推荐目标卡片：主图标 + 标题/描述 + 元信息徽章 + 加号按钮。
class _RecommendedGoalCard extends StatelessWidget {
  final RecommendedGoal goal;
  final VoidCallback? onApply;
  final bool pending;

  const _RecommendedGoalCard({
    required this.goal,
    required this.onApply,
    required this.pending,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = Color(goal.colorValue);
    final icon = goalIconFromName(goal.icon);

    return AppSurfaceCard(
      key: ValueKey('recommended-goal-${goal.id}'),
      onTap: onApply,
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(DesignTokens.spaceLg),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scaler = MediaQuery.textScalerOf(context);
          final titleScale =
              scaler.scale(DesignTokens.fontSizeMd) / DesignTokens.fontSizeMd;
          final isStacked = (constraints.maxWidth - 112) < 160 * titleScale;

          final surfaceStyle = appSurfaceStyleOf(context);
          final iconBox = Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(
                surfaceStyle?.smallTileRadius ?? DesignTokens.radiusControl,
              ),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: color, size: 22),
          );

          final addButton = IconButton(
            key: ValueKey('recommended-add-${goal.id}'),
            tooltip: pending
                ? RecommendedGoalsUiCopy.adding
                : RecommendedGoalsUiCopy.add,
            icon: pending
                ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: color,
                      semanticsLabel: RecommendedGoalsUiCopy.adding,
                    ),
                  )
                : Icon(Icons.add_circle_outline, color: color),
            onPressed: onApply,
          );

          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                goal.localizedTitle,
                style: TextStyle(
                  fontSize: DesignTokens.fontSizeMd,
                  fontWeight: DesignTokens.fontWeightRegular,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: DesignTokens.spaceXxs),
              Text(
                goal.localizedDescription,
                style: TextStyle(
                  fontSize: DesignTokens.fontSizeSm,
                  color: appSecondaryDescriptionColor(context),
                  height: 1.35,
                ),
              ),
              const SizedBox(height: DesignTokens.spaceSm),
              _MetaBadges(goal: goal, baseColor: color),
            ],
          );

          if (isStacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [iconBox, addButton],
                ),
                const SizedBox(height: DesignTokens.spaceMd),
                details,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              iconBox,
              const SizedBox(width: DesignTokens.spaceMd),
              Expanded(child: details),
              const SizedBox(width: DesignTokens.spaceSm),
              addButton,
            ],
          );
        },
      ),
    );
  }
}

/// 第二行元信息：重复规则、节假日跳过、专注/闹钟/次数/目标时长。
class _MetaBadges extends StatelessWidget {
  final RecommendedGoal goal;
  final Color baseColor;

  const _MetaBadges({required this.goal, required this.baseColor});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final badges = <Widget>[];

    // 重复规则 + 调度模式
    final recurrenceLabel = RecommendedGoalsUiCopy.recurrence(
      goal.recurrence,
      goal.scheduling,
    );
    badges.add(
      _Badge(icon: Icons.repeat, label: recurrenceLabel, color: baseColor),
    );

    // 跳过节假日
    if (goal.skipHolidays) {
      badges.add(
        _Badge(
          icon: Icons.beach_access,
          label: RecommendedGoalsUiCopy.skipHolidays,
          color: cs.secondary,
        ),
      );
    }

    // 专注联动（番茄钟）
    if (goal.focusLink.enabled) {
      badges.add(
        _Badge(
          icon: Icons.timer,
          label: RecommendedGoalsUiCopy.focus(goal.focusLink.focusSeconds),
          color: cs.primary,
        ),
      );
    }

    // 提醒（push / alarm）
    if (goal.reminder.enabled) {
      badges.add(
        _Badge(
          icon: goal.reminder.kind == ReminderKind.alarm
              ? Icons.alarm
              : goal.reminder.kind == ReminderKind.popup
              ? Icons.open_in_new
              : Icons.notifications_active,
          label: RecommendedGoalsUiCopy.reminder(goal.reminder),
          color: goal.reminder.kind == ReminderKind.alarm
              ? (isDark ? const Color(0xFFEF9A9A) : DesignTokens.defaultError)
              : (isDark ? const Color(0xFF90CAF9) : DesignTokens.defaultInfo),
        ),
      );
    }

    // 每日次数
    if (goal.dailyTargetCount != null && goal.dailyTargetCount! > 0) {
      badges.add(
        _Badge(
          icon: Icons.format_list_numbered,
          label: '×${goal.dailyTargetCount}',
          color: isDark ? const Color(0xFF80CBC4) : DesignTokens.defaultAccent,
        ),
      );
    }

    // 目标时长
    if (goal.timeTargetSeconds != null && goal.timeTargetSeconds! > 0) {
      badges.add(
        _Badge(
          icon: Icons.hourglass_bottom,
          label: RecommendedGoalsUiCopy.duration(goal.timeTargetSeconds!),
          color: isDark ? const Color(0xFFFFCC80) : DesignTokens.defaultWarning,
        ),
      );
    }

    return Wrap(
      spacing: DesignTokens.spaceXs,
      runSpacing: DesignTokens.spaceXs,
      children: badges,
    );
  }
}

/// 小号圆角标签。
class _Badge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _Badge({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final surfaceStyle = appSurfaceStyleOf(context);
    final isDark = theme.brightness == Brightness.dark;
    final routeBackground = isDark
        ? cs.surface
        : cs.surfaceContainerLowest;
    final cardFill = surfaceStyle?.cardFillColor ?? cs.surface;
    final cardBg = Color.alphaBlend(cardFill, routeBackground);
    final pillBg = Color.alphaBlend(color.withValues(alpha: 0.10), cardBg);
    final labelColor = appReadableForeground(pillBg, cs.onSurface);
    final iconColor = appReadableForeground(pillBg, color);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spaceSm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: DesignTokens.borderRadiusSm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: iconColor),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: DesignTokens.fontSizeXs,
                fontWeight: DesignTokens.fontWeightRegular,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: labelColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 空类别提示（理论上 5 个主类别每类 ≥ 5 条，不会触达；保底兜底）。
class _EmptyCategoryPlaceholder extends StatelessWidget {
  final GoalCategory category;
  const _EmptyCategoryPlaceholder({required this.category});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(DesignTokens.spaceXxl),
      child: EmptyState(
        icon: Icons.inbox_outlined,
        message: RecommendedGoalsUiCopy.empty(category),
      ),
    );
  }
}

/// A request and its retained View action keep the authority that rendered them.
class _RecommendationOperation {
  _RecommendationOperation(this.context, this.origin)
    : _lock = context.read<AppLockProvider?>(),
      _update = context.read<AppUpdateService?>() {
    _client = _clientSnapshot();
    for (final notifier in [
      origin.provider,
      origin.auth,
      _lock,
      _update,
      origin.share,
    ]) {
      if (notifier != null) {
        _notifiers.add(notifier);
        notifier.addListener(_observeAuthority);
      }
    }
    AccountLocalDataCleaner.accountDataGenerationListenable.addListener(
      _observeAuthority,
    );
    origin.route?.secondaryAnimation?.addListener(_observeCover);
    for (final observer in Navigator.of(context).widget.observers) {
      if (observer is AppAccessRouteGate) {
        _gates.add(observer);
        observer.routeRevision.addListener(_observeRoute);
      }
    }
  }

  final BuildContext context;
  final GoalEditorOrigin origin;
  final AppLockProvider? _lock;
  final AppUpdateService? _update;
  final _notifiers = <ChangeNotifier>[];
  final _gates = <AppAccessRouteGate>[];
  late final Object _client;
  ModalRoute<dynamic>? sheetRoute;
  bool _expired = false;
  bool _disposed = false;

  Object _clientSnapshot() => (
    origin.auth?.client,
    origin.auth?.client.token,
    origin.auth?.client.baseUrl,
    origin.auth?.state.token,
  );

  void own(ModalRoute<dynamic> route) {
    sheetRoute = route;
  }

  void listenForCover() {
    sheetRoute?.secondaryAnimation?.addListener(_observeCover);
  }

  void release(ModalRoute<dynamic> route) {
    route.secondaryAnimation?.removeListener(_observeCover);
    if (identical(sheetRoute, route)) {
      sheetRoute = null;
    }
  }

  void _observeAuthority() {
    if (_disposed || _expired) return;
    if (!context.mounted ||
        !origin.isCurrent(context, checkRoute: false) ||
        !identical(context.read<AppLockProvider?>(), _lock) ||
        !identical(context.read<AppUpdateService?>(), _update) ||
        !origin.canEdit('private') ||
        _clientSnapshot() != _client) {
      _invalidate();
    }
  }

  void _observeRoute() {
    if (_disposed || _expired) return;
    final sheet = sheetRoute;
    for (final gate in _gates) {
      final current = gate.currentRoute;
      if (!identical(current, origin.route) &&
          (sheet == null || !identical(current, sheet))) {
        _invalidate();
        return;
      }
    }
  }

  void _observeCover() {
    if (_disposed || _expired) return;
    final sheet = sheetRoute;
    if (sheet != null) {
      if ((sheet.secondaryAnimation?.value ?? 0) > 0) {
        _invalidate();
      }
    } else {
      if ((origin.route?.secondaryAnimation?.value ?? 0) > 0) {
        _invalidate();
      }
    }
  }

  void _invalidate() {
    if (_expired || _disposed) return;
    _expired = true;
    final owned = sheetRoute;
    if (owned != null) {
      void close() {
        final navigator = owned.navigator;
        if (owned.isActive && navigator?.mounted == true) {
          navigator!.removeRoute(owned);
        }
      }

      scheduleMicrotask(() {
        if (SchedulerBinding.instance.schedulerPhase ==
            SchedulerPhase.persistentCallbacks) {
          WidgetsBinding.instance.addPostFrameCallback((_) => close());
        } else {
          close();
        }
      });
    }
  }

  bool isCurrent() {
    if (_disposed || _expired || !context.mounted) return false;
    _observeAuthority();
    _observeRoute();
    _observeCover();
    if (_expired) return false;
    final sheet = sheetRoute;
    if (sheet != null) {
      if (origin.route?.isActive == false) {
        _invalidate();
        return false;
      }
      return origin.isCurrent(context, checkRoute: false);
    }
    return origin.isCurrent(context);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    AccountLocalDataCleaner.accountDataGenerationListenable.removeListener(
      _observeAuthority,
    );
    origin.route?.secondaryAnimation?.removeListener(_observeCover);
    final sheet = sheetRoute;
    sheet?.secondaryAnimation?.removeListener(_observeCover);
    sheetRoute = null;
    for (final notifier in _notifiers) {
      notifier.removeListener(_observeAuthority);
    }
    for (final gate in _gates) {
      gate.routeRevision.removeListener(_observeRoute);
    }
  }
}
