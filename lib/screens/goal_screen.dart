import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/design_tokens.dart';
import '../core/desktop_tokens.dart';
import '../core/i18n.dart';
import '../core/goal_icons.dart';
import '../core/image_decode_cache.dart';
import '../models/goal.dart';
import '../providers/goal_provider.dart';
import '../providers/share_provider.dart';
import '../services/goal_editor_origin.dart';
import '../widgets/brand_background.dart' show LocaleStatePreservingRoute;
import '../widgets/empty_state.dart';
import '../widgets/surface_components.dart';
import 'goal_edit_screen.dart';
import 'recommended_goals_picker.dart';

Color _goalCardBackground(BuildContext context) {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  final surfaceStyle = appSurfaceStyleOf(context);
  var background = theme.scaffoldBackgroundColor;
  for (final shadow in surfaceStyle?.cardShadow ?? const <BoxShadow>[]) {
    background = Color.alphaBlend(shadow.color, background);
  }
  final effectiveFill = surfaceStyle?.cardFillColor ?? cs.surface;
  return Color.alphaBlend(effectiveFill, background);
}

Color _ensureContrast(Color fg, Color bg, {double minContrast = 4.65}) {
  final bgLum = bg.computeLuminance();
  final curLum = fg.computeLuminance();
  final ratio =
      (math.max(curLum, bgLum) + 0.05) / (math.min(curLum, bgLum) + 0.05);
  if (ratio >= minContrast) return fg;

  var hsl = HSLColor.fromColor(fg);
  var result = fg;
  var currentRatio = ratio;
  final shouldLighten = bgLum < 0.5;

  for (var i = 0; i < 30 && currentRatio < minContrast; i++) {
    final nextL = shouldLighten
        ? (hsl.lightness + 0.02).clamp(0.0, 1.0)
        : (hsl.lightness - 0.02).clamp(0.0, 1.0);
    if ((nextL - hsl.lightness).abs() < 0.001 ||
        nextL <= 0.02 ||
        nextL >= 0.98) {
      break;
    }
    hsl = hsl.withLightness(nextL);
    result = hsl.toColor();
    final dLum = result.computeLuminance();
    currentRatio =
        (math.max(dLum, bgLum) + 0.05) / (math.min(dLum, bgLum) + 0.05);
  }
  return result;
}

Color _goalReadableProgressColor(Color color, BuildContext context) {
  final cardBg = _goalCardBackground(context);
  return _ensureContrast(color, cardBg, minContrast: 4.65);
}

Color _goalReadableStatusColor(Color statusColor, BuildContext context) {
  final cardBg = _goalCardBackground(context);
  final pillBg =
      Color.alphaBlend(statusColor.withValues(alpha: 0.12), cardBg);
  return _ensureContrast(statusColor, pillBg, minContrast: 4.65);
}

Color _goalReadableSharedBadgeColor(BuildContext context, Color primary) {
  final cardBg = _goalCardBackground(context);
  final badgeBg = Color.alphaBlend(primary.withValues(alpha: 0.10), cardBg);
  return _ensureContrast(primary, badgeBg, minContrast: 4.65);
}

Color _goalReadableDeadlineColor(Color color, BuildContext context) {
  final cardBg = _goalCardBackground(context);
  return _ensureContrast(color, cardBg, minContrast: 4.65);
}

Color _goalReadableSecondaryText(BuildContext context) {
  final cardBg = _goalCardBackground(context);
  final fallback = Theme.of(context).colorScheme.onSurfaceVariant;
  return _ensureContrast(fallback, cardBg, minContrast: 4.65);
}

enum _GoalStatusFilter { all, active, achieved, paused }

enum _GoalSortOrder { defaultOrder, deadlineSoonest, progressDesc, progressAsc }

class GoalScreen extends StatefulWidget implements LocaleStatePreservingRoute {
  final String? initialGoalId;

  const GoalScreen({super.key, this.initialGoalId});

  @override
  State<GoalScreen> createState() => _GoalScreenState();
}

class _GoalScreenState extends State<GoalScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  _GoalStatusFilter _statusFilter = _GoalStatusFilter.all;
  _GoalSortOrder _sortOrder = _GoalSortOrder.defaultOrder;
  String _searchQuery = '';
  String? _highlightedGoalId;
  String? _scrolledGoalId;
  final Map<String, GlobalKey> _cardKeys = <String, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    _highlightedGoalId = widget.initialGoalId;
    I18n.localeListenable.addListener(_onLocaleChanged);
  }

  @override
  void didUpdateWidget(covariant GoalScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialGoalId != widget.initialGoalId) {
      _highlightedGoalId = widget.initialGoalId;
      _scrolledGoalId = null;
      if (_highlightedGoalId != null) {
        _statusFilter = _GoalStatusFilter.all;
        _searchQuery = '';
        _searchController.clear();
      }
    }
  }

  @override
  void dispose() {
    I18n.localeListenable.removeListener(_onLocaleChanged);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  GlobalKey _keyForGoal(String id) =>
      _cardKeys.putIfAbsent(id, () => GlobalKey());

  void _scheduleHighlightScroll(List<GoalItem> visibleGoals) {
    final targetId = _highlightedGoalId;
    if (targetId == null || targetId.isEmpty || _scrolledGoalId == targetId) {
      return;
    }
    final targetIndex = visibleGoals.indexWhere((g) => g.id == targetId);
    if (targetIndex < 0) return;
    _scrolledGoalId = targetId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final cardContext = _cardKeys[targetId]?.currentContext;
      if (cardContext != null) {
        Scrollable.ensureVisible(
          cardContext,
          duration: const Duration(milliseconds: 220),
          alignment: 0.15,
        );
        return;
      }
      if (_scrollController.hasClients && targetIndex > 0) {
        final maxExtent = _scrollController.position.maxScrollExtent;
        final estimated = (targetIndex * 180.0).clamp(0.0, maxExtent);
        _scrollController.jumpTo(estimated);
      }
    });
  }

  int? _goalsFilterFingerprint;
  String? _goalsFilterQuery;
  _GoalStatusFilter? _goalsFilterStatus;
  _GoalSortOrder? _goalsSortCached;
  List<GoalItem>? _filteredGoalsCached;

  int _goalsFingerprint(List<GoalItem> allGoals) {
    var fp = allGoals.length;
    for (final g in allGoals) {
      fp = Object.hash(
        fp,
        g.id,
        g.status.index,
        g.updatedAt.millisecondsSinceEpoch,
        g.milestones.length,
      );
    }
    return fp;
  }

  List<GoalItem> _filterAndSortGoals(List<GoalItem> allGoals) {
    final fp = _goalsFingerprint(allGoals);
    final query = _searchQuery.trim().toLowerCase();
    final cached = _filteredGoalsCached;
    if (cached != null &&
        _goalsFilterFingerprint == fp &&
        _goalsFilterQuery == query &&
        _goalsFilterStatus == _statusFilter &&
        _goalsSortCached == _sortOrder) {
      return cached;
    }
    final filtered = allGoals.where((goal) {
      final matchesStatus = switch (_statusFilter) {
        _GoalStatusFilter.all => true,
        _GoalStatusFilter.active => goal.status == GoalStatus.active,
        _GoalStatusFilter.achieved => goal.status == GoalStatus.achieved,
        _GoalStatusFilter.paused => goal.status == GoalStatus.paused,
      };
      if (!matchesStatus) return false;
      if (query.isEmpty) return true;
      if (goal.title.toLowerCase().contains(query)) return true;
      if (goal.description.toLowerCase().contains(query)) return true;
      return goal.milestones.any(
        (m) => m.title.toLowerCase().contains(query),
      );
    }).toList();

    switch (_sortOrder) {
      case _GoalSortOrder.defaultOrder:
        break;
      case _GoalSortOrder.deadlineSoonest:
        filtered.sort((a, b) {
          final aDate = a.targetDate;
          final bDate = b.targetDate;
          if (aDate == null && bDate == null) return 0;
          if (aDate == null) return 1;
          if (bDate == null) return -1;
          return aDate.compareTo(bDate);
        });
      case _GoalSortOrder.progressDesc:
        filtered.sort(
          (a, b) => b.computedProgress.compareTo(a.computedProgress),
        );
      case _GoalSortOrder.progressAsc:
        filtered.sort(
          (a, b) => a.computedProgress.compareTo(b.computedProgress),
        );
    }
    final result = List<GoalItem>.unmodifiable(filtered);
    _goalsFilterFingerprint = fp;
    _goalsFilterQuery = query;
    _goalsFilterStatus = _statusFilter;
    _goalsSortCached = _sortOrder;
    _filteredGoalsCached = result;
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GoalProvider>();
    final recommendedOrigin = GoalEditorOrigin.capture(context);
    final allGoals = provider.goals;
    final visibleGoals = _filterAndSortGoals(allGoals);
    _scheduleHighlightScroll(visibleGoals);
    final isEn = I18n.current == AppLocale.en;
    final dpr = MediaQuery.devicePixelRatioOf(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              goalFeatureIconAsset,
              width: 24,
              height: 24,
              cacheWidth: ImageDecodeCache.boundedCachePixels(24, dpr),
              cacheHeight: ImageDecodeCache.boundedCachePixels(24, dpr),
              gaplessPlayback: true,
            ),
            const SizedBox(width: 8),
            Text(I18n.tr('goal.title')),
          ],
        ),
        actions: [
          IconButton(
            tooltip: I18n.tr('goal.recommended_templates'),
            icon: const Icon(Icons.auto_awesome),
            onPressed: () {
              if (recommendedOrigin.isCurrent(context)) {
                _openRecommended(context);
              }
            },
          ),
        ],
      ),
      body: allGoals.isEmpty
          ? EmptyState(
              icon: Icons.flag_circle_outlined,
              iconWidget: Image.asset(
                goalFeatureIconAsset,
                width: 40,
                height: 40,
                cacheWidth: ImageDecodeCache.boundedCachePixels(40, dpr),
                cacheHeight: ImageDecodeCache.boundedCachePixels(40, dpr),
                gaplessPlayback: true,
              ),
              message: I18n.tr('goal.empty'),
              actionLabel: I18n.tr('goal.create'),
              onAction: () => _openEdit(context),
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: DesktopTokens.secondaryMaxContentWidth,
                ),
                child: ListView.builder(
                  controller: _scrollController,
                  padding: EdgeInsets.fromLTRB(
                    12,
                    12,
                    12,
                    MediaQuery.paddingOf(context).bottom + 88,
                  ),
                  itemCount: 1 + (visibleGoals.isEmpty ? 1 : visibleGoals.length),
                  itemBuilder: (_, i) {
                    if (i == 0) {
                      return _buildFilterAndSearchHeader(context, isEn);
                    }
                    if (visibleGoals.isEmpty) {
                      return _buildNoFilterMatches(context, isEn);
                    }
                    final goal = visibleGoals[i - 1];
                    return _GoalCard(
                      key: _keyForGoal(goal.id),
                      goal: goal,
                      highlighted: goal.id == _highlightedGoalId,
                      onToggleMilestone: (milestoneId) =>
                          _toggleMilestone(provider, goal.id, milestoneId),
                    );
                  },
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'goal_add_fab',
        onPressed: () => _openEdit(context),
        icon: const Icon(Icons.add),
        label: Text(I18n.tr('goal.new')),
      ),
    );
  }

  Widget _buildFilterAndSearchHeader(BuildContext context, bool isEn) {
    final cs = Theme.of(context).colorScheme;
    final statusLabels = <(_GoalStatusFilter, String)>[
      (_GoalStatusFilter.all, isEn ? 'All' : '全部'),
      (_GoalStatusFilter.active, isEn ? 'Active' : '进行中'),
      (_GoalStatusFilter.achieved, isEn ? 'Achieved' : '已达成'),
      (_GoalStatusFilter.paused, isEn ? 'Paused' : '已暂停'),
    ];
    final sortLabel = switch (_sortOrder) {
      _GoalSortOrder.defaultOrder => isEn ? 'Default' : '默认排序',
      _GoalSortOrder.deadlineSoonest => isEn ? 'Deadline' : '截止日期',
      _GoalSortOrder.progressDesc => isEn ? 'Progress ↓' : '进度降序',
      _GoalSortOrder.progressAsc => isEn ? 'Progress ↑' : '进度升序',
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('goal_search_field'),
                  controller: _searchController,
                  onChanged: (value) => setState(() => _searchQuery = value),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: isEn
                        ? 'Search goals or milestones...'
                        : '搜索目标标题、描述或里程碑...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: _searchQuery.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: cs.outlineVariant,
                        width: 0.6,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: cs.outlineVariant,
                        width: 0.6,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<_GoalSortOrder>(
                key: const ValueKey('goal_sort_button'),
                initialValue: _sortOrder,
                tooltip: isEn ? 'Sort goals' : '目标排序',
                onSelected: (value) => setState(() => _sortOrder = value),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: _GoalSortOrder.defaultOrder,
                    child: Text(isEn ? 'Default order' : '默认排序'),
                  ),
                  PopupMenuItem(
                    value: _GoalSortOrder.deadlineSoonest,
                    child: Text(isEn ? 'Deadline soonest' : '截止日期最近'),
                  ),
                  PopupMenuItem(
                    value: _GoalSortOrder.progressDesc,
                    child: Text(isEn ? 'Highest progress' : '进度从高到低'),
                  ),
                  PopupMenuItem(
                    value: _GoalSortOrder.progressAsc,
                    child: Text(isEn ? 'Lowest progress' : '进度从低到高'),
                  ),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cs.outlineVariant, width: 0.6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.sort_rounded, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        sortLabel,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (filter, label) in statusLabels) ...[
                  ChoiceChip(
                    key: ValueKey('goal_filter_${filter.name}'),
                    label: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                    selected: _statusFilter == filter,
                    onSelected: (_) => setState(() => _statusFilter = filter),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoFilterMatches(BuildContext context, bool isEn) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.filter_list_off, size: 36, color: cs.outline),
          const SizedBox(height: 10),
          Text(
            isEn ? 'No matching goals' : '没有符合条件的目标',
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.normal,
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () {
              _searchController.clear();
              setState(() {
                _searchQuery = '';
                _statusFilter = _GoalStatusFilter.all;
                _sortOrder = _GoalSortOrder.defaultOrder;
              });
            },
            child: Text(isEn ? 'Reset filters' : '重置筛选'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleMilestone(
    GoalProvider provider,
    String goalId,
    String milestoneId,
  ) async {
    try {
      await provider.toggleMilestone(goalId, milestoneId);
    } catch (error) {
      if (!mounted) return;
      final isEn = I18n.current == AppLocale.en;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is StateError
                ? error.message
                : (isEn ? 'Unable to update milestone' : '无法更新里程碑状态'),
          ),
        ),
      );
    }
  }

  void _openEdit(BuildContext context, {GoalItem? goal}) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GoalEditScreen(goal: goal)),
    );
  }

  void _openRecommended(BuildContext context) {
    Navigator.push<GoalItem>(
      context,
      MaterialPageRoute<GoalItem>(
        builder: (_) => const RecommendedGoalsPicker(),
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  final GoalItem goal;
  final bool highlighted;
  final ValueChanged<String>? onToggleMilestone;

  const _GoalCard({
    super.key,
    required this.goal,
    this.highlighted = false,
    this.onToggleMilestone,
  });

  Color _statusColor(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return switch (goal.status) {
      GoalStatus.active => DesignTokens.defaultSuccess,
      GoalStatus.paused => cs.onSurfaceVariant,
      GoalStatus.achieved => DesignTokens.defaultWarning,
      GoalStatus.abandoned => cs.error,
    };
  }

  String _statusText() => switch (goal.status) {
    GoalStatus.active => I18n.tr('goal.status.active'),
    GoalStatus.paused => I18n.tr('goal.status.paused'),
    GoalStatus.achieved => I18n.tr('goal.status.achieved'),
    GoalStatus.abandoned => I18n.tr('goal.status.abandoned'),
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final surfaceStyle = appSurfaceStyleOf(context);
    final color = Color(goal.colorValue);
    final progress = goal.computedProgress;
    final days = goal.daysRemaining;
    final hasDeadline = goal.targetDate != null;
    final deadlineLabel = hasDeadline
        ? (days >= 0
              ? '${I18n.tr('goal.days_remaining.prefix')}$days'
                    '${I18n.tr('goal.days_remaining.suffix')}'
              : '${I18n.tr('goal.overdue.prefix')}${-days}'
                    '${I18n.tr('goal.overdue.suffix')}')
        : (I18n.current == AppLocale.en ? 'No deadline' : '无期限');
    final deadlineColor = !hasDeadline || days >= 0
        ? cs.onSurfaceVariant
        : cs.error;
    final shareProvider = context.watch<ShareProvider?>();
    final isShared =
        goal.workspaceId.trim().isNotEmpty &&
        goal.workspaceId.trim() != 'private';
    final statusColor = _statusColor(context);

    return AppSurfaceCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      borderRadius: BorderRadius.circular(
        surfaceStyle?.cardRadius ?? DesignTokens.radiusCard,
      ),
      border: highlighted
          ? Border.all(color: cs.primary, width: 0.6)
          : null,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => GoalEditScreen(goal: goal)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final effectiveProgressColor =
              _goalReadableProgressColor(color, context);
          final effectiveDeadlineColor =
              _goalReadableDeadlineColor(deadlineColor, context);
          final secondaryTextColor = _goalReadableSecondaryText(context);
          final readableStatusColor =
              _goalReadableStatusColor(statusColor, context);
          final textScale = MediaQuery.textScalerOf(context).scale(1.0);
          final isStackedHeader =
              textScale >= 1.35 ||
              (constraints.maxWidth < 360 && textScale >= 1.2);

          Widget buildStatusPill() => Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              _statusText(),
              style: TextStyle(
                fontSize: 11,
                color: readableStatusColor,
                fontWeight: FontWeight.normal,
              ),
            ),
          );

          Widget buildIconBox() => Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(
                surfaceStyle?.smallTileRadius ?? DesignTokens.radiusControl,
              ),
            ),
            child: Icon(goalIconFromName(goal.icon), color: color),
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isStackedHeader)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    buildIconBox(),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            goal.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                          if (goal.description.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              goal.description,
                              style: TextStyle(
                                fontSize: 12,
                                color: secondaryTextColor,
                                fontWeight: FontWeight.normal,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (isShared)
                                _SharedGoalBadge(
                                  label: _workspaceLabel(
                                    shareProvider,
                                    goal.workspaceId.trim(),
                                  ),
                                ),
                              buildStatusPill(),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    buildIconBox(),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  goal.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.normal,
                                  ),
                                ),
                              ),
                              if (isShared) ...[
                                const SizedBox(width: 6),
                                _SharedGoalBadge(
                                  label: _workspaceLabel(
                                    shareProvider,
                                    goal.workspaceId.trim(),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (goal.description.isNotEmpty)
                            Text(
                              goal.description,
                              style: TextStyle(
                                fontSize: 12,
                                color: secondaryTextColor,
                                fontWeight: FontWeight.normal,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    buildStatusPill(),
                  ],
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: color.withValues(alpha: 0.1),
                        color: color,
                        minHeight: 8,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${(progress * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      color: effectiveProgressColor,
                      fontWeight: FontWeight.normal,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _GoalMetaChip(
                    icon: Icons.check_circle_outline,
                    label:
                        '${I18n.tr('goal.milestone.prefix')}'
                        '${goal.milestones.where((m) => m.isCompleted).length}/'
                        '${goal.milestones.length}',
                    color: secondaryTextColor,
                  ),
                  _GoalMetaChip(
                    icon: hasDeadline ? Icons.schedule : Icons.all_inclusive,
                    label: deadlineLabel,
                    color: effectiveDeadlineColor,
                  ),
                ],
              ),
              if (goal.milestones.isNotEmpty) ...[
                const SizedBox(height: 8),
                Column(
                  children: [
                    for (final milestone in goal.milestones)
                      InkWell(
                        key: ValueKey(
                          'goal_inline_milestone_${goal.id}_${milestone.id}',
                        ),
                        borderRadius: BorderRadius.circular(8),
                        onTap: onToggleMilestone == null
                            ? null
                            : () => onToggleMilestone!(milestone.id),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 28,
                                height: 28,
                                child: Checkbox(
                                  value: milestone.isCompleted,
                                  onChanged: onToggleMilestone == null
                                      ? null
                                      : (_) => onToggleMilestone!(milestone.id),
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  milestone.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: secondaryTextColor,
                                    decoration: milestone.isCompleted
                                        ? TextDecoration.lineThrough
                                        : null,
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
              ],
            ],
          );
        },
      ),
    );
  }

  String _workspaceLabel(ShareProvider? provider, String workspaceId) {
    for (final workspace in provider?.workspaces ?? const []) {
      if (workspace.id == workspaceId) return workspace.name;
    }
    return I18n.current == AppLocale.en ? 'Shared' : '共享';
  }
}

class _GoalMetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _GoalMetaChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.normal,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

class _SharedGoalBadge extends StatelessWidget {
  final String label;

  const _SharedGoalBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final badgeColor = _goalReadableSharedBadgeColor(context, cs.primary);
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spaceXs,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: cs.primary.withValues(alpha: 0.24),
          width: 0.45,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.groups_2_outlined, size: 12, color: badgeColor),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: DesignTokens.fontSizeXs,
                color: badgeColor,
                fontWeight: FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
