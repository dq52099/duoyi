import 'package:duoyi/desktop_web/desktop_embedded_scope.dart';

import '../core/almanac_locale_format.dart';
import '../core/design_tokens.dart' show AppSurfaceStyle, DesignTokens;
import '../widgets/brand_background.dart';
import '../core/date_item_ui_copy.dart';
import '../services/date_item_action_origin.dart';
import '../widgets/date_item_feedback.dart';
import '../widgets/app_date_format.dart';
import 'package:flutter/material.dart';
import '../core/i18n.dart';
import '../core/i18n_date_format.dart';
import 'package:provider/provider.dart';
import '../models/anniversary.dart';
import '../models/goal.dart'
    show ReminderKind, normalizeUserSelectableReminderKind;
import '../providers/anniversary_provider.dart';
import '../providers/notification_service.dart';
import '../services/alarm_service.dart';
import '../services/local_notifications.dart';
import '../core/lunar_calendar.dart';
import '../widgets/app_date_picker.dart';
import '../widgets/app_time_picker.dart';
import '../widgets/empty_state.dart';
import '../widgets/surface_components.dart';

Future<void> showAnniversaryEditor(
  BuildContext context, {
  Anniversary? item,
  AnniversaryType? fixedType,
}) {
  final editorType =
      item?.type ??
      (fixedType == AnniversaryType.normal
          ? AnniversaryType.memorial
          : fixedType);
  return showAppModalSheet<void>(
    context: context,
    builder: (_) => _AnniversaryEditSheet(editing: item, fixedType: editorType),
  );
}

class AnniversaryScreen extends StatefulWidget
    implements LocaleStatePreservingRoute {
  final int initialTab;
  final AnniversaryType? fixedType;
  final String? initialAnniversaryId;

  const AnniversaryScreen({
    super.key,
    this.initialTab = 0,
    this.fixedType,
    this.initialAnniversaryId,
  });

  @override
  State<AnniversaryScreen> createState() => _AnniversaryScreenState();
}

class _AnniversaryScreenState extends State<AnniversaryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  late int _tabIndex;
  bool _openedInitialAnniversary = false;

  @override
  void initState() {
    super.initState();
    I18n.localeListenable.addListener(_localeChanged);
    final fixedType = widget.fixedType;
    final initialIndex = fixedType == null
        ? widget.initialTab.clamp(0, 2)
        : switch (fixedType) {
            AnniversaryType.birthday => 1,
            AnniversaryType.memorial => 2,
            AnniversaryType.normal => 0,
            AnniversaryType.custom => 0,
          };
    _tabs = TabController(length: 3, initialIndex: initialIndex, vsync: this);
    _tabIndex = _tabs.index;
    _tabs.addListener(_handleTabChanged);
  }

  void _localeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    I18n.localeListenable.removeListener(_localeChanged);
    _tabs.removeListener(_handleTabChanged);
    _tabs.dispose();
    super.dispose();
  }

  void _handleTabChanged() {
    if (_tabIndex == _tabs.index) return;
    setState(() => _tabIndex = _tabs.index);
  }

  String get _title {
    switch (_tabIndex) {
      case 1:
        return I18n.tr('anniversary.birthday');
      case 2:
        return I18n.tr('anniversary.title');
      default:
        return I18n.tr('anniversary.title');
    }
  }

  List<Anniversary> _filter(AnniversaryProvider p, int idx) {
    switch (idx) {
      case 0:
        return p.items;
      case 1:
        return p.items
            .where((e) => e.type == AnniversaryType.birthday)
            .toList();
      case 2:
        return p.items
            .where((e) => e.type == AnniversaryType.memorial)
            .toList();
      default:
        return p.items;
    }
  }

  void _openInitialAnniversaryIfNeeded(AnniversaryProvider provider) {
    if (_openedInitialAnniversary) return;
    final id = widget.initialAnniversaryId;
    if (id == null || id.isEmpty) return;
    final index = provider.items.indexWhere((item) => item.id == id);
    if (index < 0) return;
    _openedInitialAnniversary = true;
    final origin = DateItemActionOrigin.anniversary(context);
    final item = provider.items[index];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!origin.isCurrent()) return;
      showAnniversaryEditor(context, item: item, fixedType: item.type);
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AnniversaryProvider>();
    final actionOrigin = DateItemActionOrigin.anniversary(context);
    void add() {
      if (actionOrigin.isCurrent()) _showAddDialog(context);
    }

    _openInitialAnniversaryIfNeeded(provider);
    final theme = Theme.of(context);
    final cs = Theme.of(context).colorScheme;
    final routeBackground = theme.brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;
    final surfaceStyle = appSurfaceStyleOf(context);
    final isLiquidGlass = surfaceStyle == AppSurfaceStyle.liquidGlass;
    final fixedType = widget.fixedType;
    final fixedList = fixedType == null
        ? null
        : provider.items.where((e) => e.type == fixedType).toList();
    final canAdd = fixedType != AnniversaryType.normal;
    final fixedTitle = fixedType == null
        ? _title
        : switch (fixedType) {
            AnniversaryType.birthday => I18n.tr('anniversary.birthday'),
            AnniversaryType.memorial => I18n.tr('anniversary.title'),
            AnniversaryType.normal => I18n.tr('countdown.title'),
            AnniversaryType.custom => I18n.tr('anniversary.custom'),
          };

    final scaffold = Scaffold(
      backgroundColor: isLiquidGlass ? Colors.transparent : routeBackground,
      appBar: AppBar(
        title: Text(fixedTitle),
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
        backgroundColor: routeBackground.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
        bottom: fixedType == null
            ? TabBar(
                controller: _tabs,
                labelStyle: appSecondaryMenuItemTextStyle(context),
                unselectedLabelStyle: appSecondaryMenuItemTextStyle(context),
                tabs: [
                  Tab(text: I18n.tr('anniversary.tab.all')),
                  Tab(text: I18n.tr('anniversary.birthday')),
                  Tab(text: I18n.tr('anniversary.title')),
                ],
              )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.today),
            tooltip: I18n.tr('anniversary.upcoming_30_days'),
            onPressed: () {
              if (actionOrigin.isCurrent()) _showUpcoming(context, provider);
            },
          ),
        ],
      ),
      body: ColoredBox(
        color: isLiquidGlass
            ? Colors.transparent
            : routeBackground.withValues(alpha: 0.92),
        child: AppSecondaryControlTheme(
          child: fixedList == null
              ? TabBarView(
                  controller: _tabs,
                  children: List.generate(3, (i) {
                    return _AnniversaryList(
                      items: _filter(provider, i),
                      onAdd: canAdd ? add : null,
                    );
                  }),
                )
              : _AnniversaryList(
                  items: fixedList,
                  onAdd: canAdd ? add : null,
                  fixedType: fixedType,
                ),
        ),
      ),
      floatingActionButton: canAdd
          ? FloatingActionButton.extended(
              heroTag: 'anniversary_add_fab',
              onPressed: add,
              icon: const Icon(Icons.add),
              label: Text(I18n.tr('action.add')),
              backgroundColor: cs.primary,
            )
          : null,
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

  void _showUpcoming(BuildContext context, AnniversaryProvider p) {
    final up = p.upcoming;
    showAppModalSheet(
      context: context,
      builder: (sheetContext) {
        final datePattern = AppDateFormat.patternOf(sheetContext);
        return AppModalSheet(
          title: I18n.tr('anniversary.upcoming_30_days'),
          child: up.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(I18n.tr('anniversary.upcoming_empty')),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: up.length,
                  itemBuilder: (itemContext, index) {
                    final a = up[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: Color(
                          a.colorValue,
                        ).withValues(alpha: 0.2),
                        child: Text(
                          '${a.daysRemaining}',
                          style: TextStyle(
                            color: Color(a.colorValue),
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                      ),
                      title: Text(a.title),
                      subtitle: Text(
                        '${I18nDateFormat.date(a.nextOccurrence, pattern: datePattern)}'
                        '${a.yearsPassed != null ? ' · ${I18n.tr('anniversary.occurrence.prefix')}${a.yearsPassed! + 1}${I18n.tr('anniversary.occurrence.suffix')}' : ''}',
                      ),
                    );
                  },
                ),
        );
      },
    );
  }

  void _showAddDialog(BuildContext context) {
    showAnniversaryEditor(
      context,
      fixedType: widget.fixedType ?? _typeForTab ?? AnniversaryType.memorial,
    );
  }

  AnniversaryType? get _typeForTab {
    return switch (_tabIndex) {
      1 => AnniversaryType.birthday,
      2 => AnniversaryType.memorial,
      _ => null,
    };
  }
}

class BirthdayScreen extends StatelessWidget
    implements LocaleStatePreservingRoute {
  final String? initialAnniversaryId;

  const BirthdayScreen({super.key, this.initialAnniversaryId});

  @override
  Widget build(BuildContext context) {
    return AnniversaryScreen(
      fixedType: AnniversaryType.birthday,
      initialAnniversaryId: initialAnniversaryId,
    );
  }
}

class MemorialAnniversaryScreen extends StatelessWidget
    implements LocaleStatePreservingRoute {
  final String? initialAnniversaryId;

  const MemorialAnniversaryScreen({super.key, this.initialAnniversaryId});

  @override
  Widget build(BuildContext context) {
    return AnniversaryScreen(
      fixedType: AnniversaryType.memorial,
      initialAnniversaryId: initialAnniversaryId,
    );
  }
}

class _AnniversaryList extends StatelessWidget {
  final List<Anniversary> items;
  final VoidCallback? onAdd;
  final AnniversaryType? fixedType;

  const _AnniversaryList({
    required this.items,
    required this.onAdd,
    this.fixedType,
  });

  @override
  Widget build(BuildContext context) {
    final name = fixedType?.name ?? 'all';
    final cs = Theme.of(context).colorScheme;
    final titleStyle = appSecondaryRouteTitleTextStyle(context);
    final upcoming = items.where((item) => item.daysRemaining >= 0).toList()
      ..sort((a, b) => a.daysRemaining.compareTo(b.daysRemaining));
    final nearest = upcoming.isEmpty ? null : upcoming.first;
    final soonCount = items
        .where((item) => item.daysRemaining >= 0 && item.daysRemaining <= 30)
        .length;
    final listTitle = fixedType == AnniversaryType.birthday
        ? I18n.tr('anniversary.birthday')
        : fixedType == AnniversaryType.memorial
        ? I18n.tr('anniversary.title')
        : I18n.tr('anniversary.title');
    return items.isEmpty
        ? EmptyState(
            key: ValueKey('anniversary_fixed_$name'),
            icon: Icons.event,
            message: I18n.tr('anniversary.empty'),
            actionLabel: onAdd == null ? null : I18n.tr('action.add'),
            onAction: onAdd,
          )
        : CustomScrollView(
            key: ValueKey('anniversary_fixed_$name'),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  12,
                  12,
                  12,
                  items.isEmpty ? MediaQuery.paddingOf(context).bottom + 88 : 0,
                ),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppSurfaceCard(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: cs.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(
                                fixedType == AnniversaryType.birthday
                                    ? Icons.cake_outlined
                                    : Icons.event_available_outlined,
                                color: cs.primary,
                                size: 26,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(listTitle, style: titleStyle),
                                  const SizedBox(height: 4),
                                  Text(
                                    nearest == null
                                        ? I18n.tr('countdown.nearest.empty')
                                        : '${I18n.tr('countdown.nearest.prefix')}${nearest.title} · '
                                              '${I18n.tr('countdown.nearest.days_prefix')}${nearest.daysRemaining} '
                                              '${I18n.tr('unit.day')}',
                                    softWrap: true,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(color: cs.onSurface),
                                  ),
                                  const SizedBox(height: 10),
                                  _AnniversarySummaryStats(
                                    total: _AnniversarySummaryStat(
                                      key: const ValueKey(
                                        'anniversary_summary_total',
                                      ),
                                      label: I18n.tr('countdown.summary.total'),
                                      value: '${items.length}',
                                      color: cs.primary,
                                    ),
                                    soon: _AnniversarySummaryStat(
                                      key: const ValueKey(
                                        'anniversary_summary_within_30_days',
                                      ),
                                      label: I18n.tr(
                                        'anniversary.summary.within_30_days',
                                      ),
                                      value: '$soonCount',
                                      color: cs.tertiary,
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
                        title: I18n.current == AppLocale.en
                            ? '$listTitle ${I18n.tr('anniversary.list.suffix')}'
                            : '$listTitle${I18n.tr('anniversary.list.suffix')}',
                        subtitle: I18n.tr('anniversary.list.subtitle'),
                        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  12,
                  0,
                  12,
                  MediaQuery.paddingOf(context).bottom + 88,
                ),
                sliver: SliverList.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final origin = DateItemActionOrigin.anniversary(context);
                    return _AnniversaryCard(
                      key: ValueKey((origin.identity, item.id)),
                      item: item,
                      origin: origin,
                    );
                  },
                ),
              ),
            ],
          );
  }
}

class _AnniversarySummaryStats extends StatelessWidget {
  final _AnniversarySummaryStat total;
  final _AnniversarySummaryStat soon;

  const _AnniversarySummaryStats({required this.total, required this.soon});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 220.0;
        final statWidth = width >= 176 ? ((width - 14) / 2) : width;
        return Wrap(
          spacing: 14,
          runSpacing: 10,
          children: [
            SizedBox(width: statWidth, child: total),
            SizedBox(width: statWidth, child: soon),
          ],
        );
      },
    );
  }
}

class _AnniversarySummaryStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _AnniversarySummaryStat({
    super.key,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.numbers, size: 15, color: color),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          softWrap: true,
          style: appSecondaryRouteTitleTextStyle(context).copyWith(
            fontWeight: FontWeight.normal,
            color: cs.onSurface,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          softWrap: true,
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurface,
            fontWeight: FontWeight.normal,
          ),
        ),
      ],
    );
  }
}

class _AnniversaryCard extends StatefulWidget {
  final Anniversary item;

  final DateItemActionOrigin origin;

  const _AnniversaryCard({super.key, required this.item, required this.origin});

  @override
  State<_AnniversaryCard> createState() => _AnniversaryCardState();
}

class _AnniversaryCardState extends State<_AnniversaryCard>
    with DateItemMutationState<_AnniversaryCard> {
  static const double _swipeActionWidth = 82;
  static const double _swipeOpenThreshold = 32;

  double _swipeOffset = 0;
  bool _dragging = false;

  bool get _swipeOpen => _swipeOffset > 0;

  Anniversary get item => widget.item;

  @override
  void didUpdateWidget(covariant _AnniversaryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.item.id != oldWidget.item.id) {
      _swipeOffset = 0;
      _dragging = false;
    }
  }

  String _typeLabel() => switch (widget.item.type) {
    AnniversaryType.birthday => '🎂 ${I18n.tr('anniversary.birthday')}',
    AnniversaryType.memorial => '💞 ${I18n.tr('anniversary.title')}',
    AnniversaryType.normal => '⏰ ${I18n.tr('anniversary.countdown_short')}',
    AnniversaryType.custom => '🔁 ${I18n.tr('anniversary.custom')}',
  };

  void _closeSwipe() {
    if (!_swipeOpen || !mounted) return;
    setState(() => _swipeOffset = 0);
  }

  Future<void> _confirmDelete(BuildContext context) => runDateItemMutation(
    origin: widget.origin,
    failure: () => DateItemUiCopy.deleteFailed,
    confirm: (operation) =>
        confirmDateItemDeletion(operation, widget.item.title),
    write: (operation) => widget.origin.anniversaries.delete(
      widget.item.id,
      canWrite: operation.isCurrent,
    ),
    onCommitted: _closeSwipe,
  );

  Future<void> _setPinned() {
    final id = widget.item.id;
    final pinned = !widget.item.isPinned;
    final origin = widget.origin;
    return runDateItemMutation(
      origin: origin,
      failure: () => DateItemUiCopy.pinFailed,
      write: (operation) => origin.anniversaries.setPinned(
        id,
        pinned,
        canWrite: operation.isCurrent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = Color(item.colorValue);
    final days = item.daysRemaining;
    final isPast = item.type == AnniversaryType.normal && days < 0;
    final next = item.nextOccurrence;
    final lunar = LunarCalendar.fromSolar(next);
    final titleStyle = appSecondaryRouteTitleTextStyle(context);
    final metaStyle = appSecondaryControlLabelStyle(
      context,
    ).copyWith(color: cs.onSurface);

    final content = InkWell(
      onTap: _swipeOpen
          ? _closeSwipe
          : () {
              if (!mounted || !widget.origin.isCurrent()) return;
              showAnniversaryEditor(context, item: item, fixedType: item.type);
            },
      onLongPress: _setPinned,
      borderRadius: BorderRadius.circular(14),
      child: AppSurfaceCard(
        margin: const EdgeInsets.only(bottom: 12),
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.12), width: 0.45),
        child: Stack(
          children: [
            Positioned.fill(
              right: null,
              child: Container(
                width: 5,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: isPast ? 0.42 : 0.72),
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(14),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final stacked =
                      constraints.maxWidth < 330 ||
                      MediaQuery.textScalerOf(context).scale(14) > 20;
                  return Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: stacked
                            ? constraints.maxWidth
                            : constraints.maxWidth - 120,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (item.isPinned)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: Icon(
                                      Icons.push_pin,
                                      size: 14,
                                      color: color,
                                    ),
                                  ),
                                Expanded(
                                  child: Text(
                                    item.title,
                                    style: titleStyle,
                                    softWrap: true,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                _AnniversaryPill(
                                  label: _typeLabel(),
                                  color: color,
                                ),
                                if (item.calendarType ==
                                    AnniversaryCalendarType.lunar)
                                  _AnniversaryPill(
                                    label: I18n.tr('calendar.lunar'),
                                    color: DesignTokens.defaultWarning,
                                  ),
                                if (item.yearsPassed != null &&
                                    item.yearsPassed! > 0)
                                  Text(
                                    '${I18n.tr('anniversary.years_elapsed.prefix')}${item.yearsPassed}${I18n.tr('anniversary.years_elapsed.suffix')}',
                                    style: metaStyle,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              item.calendarType == AnniversaryCalendarType.lunar
                                  ? '${I18n.tr('anniversary.next.prefix')}${AppDateFormat.date(context, next)} (${I18n.tr('calendar.chinese_lunar')}: ${AlmanacLocaleFormat.formatLunarDate(lunar)})'
                                  : '${I18n.tr('anniversary.next.prefix')}${AppDateFormat.date(context, next)}',
                              style: metaStyle,
                            ),
                            if (item.description != null &&
                                item.description!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  item.description!,
                                  softWrap: true,
                                  style: metaStyle,
                                ),
                              ),
                          ],
                        ),
                      ),
                      ConstrainedBox(
                        constraints: const BoxConstraints(
                          minWidth: 54,
                          maxWidth: 108,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              isPast
                                  ? I18n.tr('countdown.days.elapsed')
                                  : (days == 0
                                        ? I18n.tr('today.anniversary.today')
                                        : I18n.tr('countdown.days.remaining')),
                              style: metaStyle,
                            ),
                            const SizedBox(height: 2),
                            Wrap(
                              alignment: WrapAlignment.end,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 3,
                              runSpacing: 4,
                              children: [
                                Text(
                                  days == 0
                                      ? I18n.tr('anniversary.today_short')
                                      : days.abs().toString(),
                                  style: TextStyle(
                                    fontSize: days == 0 ? 14 : 18,
                                    height: 1,
                                    fontWeight: FontWeight.normal,
                                    color: cs.onSurface,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                                if (days != 0) ...[
                                  Text(
                                    I18n.tr('unit.day'),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: cs.onSurface,
                                      fontWeight: FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    return dateItemStatus(
      GestureDetector(
        key: ValueKey('anniversary_card_${item.id}'),
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) => setState(() => _dragging = true),
        onHorizontalDragUpdate: (details) {
          final nextOffset = (_swipeOffset - details.delta.dx).clamp(
            0.0,
            _swipeActionWidth,
          );
          if (nextOffset == _swipeOffset) return;
          setState(() => _swipeOffset = nextOffset);
        },
        onHorizontalDragEnd: (_) {
          final shouldOpen = _swipeOffset >= _swipeOpenThreshold;
          setState(() {
            _dragging = false;
            _swipeOffset = shouldOpen ? _swipeActionWidth : 0;
          });
        },
        onHorizontalDragCancel: () => setState(() {
          _dragging = false;
          _swipeOffset = _swipeOffset >= _swipeOpenThreshold
              ? _swipeActionWidth
              : 0;
        }),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            if (_swipeOffset > 0)
              Positioned.fill(
                child: _AnniversaryInlineSwipeActions(
                  margin: const EdgeInsets.only(bottom: 12),
                  onDelete: () => _confirmDelete(context),
                ),
              ),
            AnimatedContainer(
              duration: _dragging
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              transform: Matrix4.translationValues(-_swipeOffset, 0, 0),
              child: content,
            ),
          ],
        ),
      ),
    );
  }
}

class _AnniversaryInlineSwipeActions extends StatelessWidget {
  final EdgeInsetsGeometry margin;
  final VoidCallback onDelete;

  const _AnniversaryInlineSwipeActions({
    required this.margin,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: margin,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: _AnniversaryCardState._swipeActionWidth,
        height: double.infinity,
        child: _AnniversaryInlineSwipeButton(
          key: const ValueKey('anniversary_swipe_delete_button'),
          icon: Icons.delete_outline,
          label: I18n.tr('action.delete'),
          background: cs.errorContainer.withValues(alpha: 0.86),
          foreground: cs.onErrorContainer,
          onTap: onDelete,
        ),
      ),
    );
  }
}

class _AnniversaryInlineSwipeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  const _AnniversaryInlineSwipeButton({
    super.key,
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: foreground,
      fontWeight: FontWeight.normal,
      height: 1.1,
    );
    return Material(
      color: background,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: foreground),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textStyle,
            ),
          ],
        ),
      ),
    );
  }
}

class _AnniversaryPill extends StatelessWidget {
  final String label;
  final Color color;

  const _AnniversaryPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 180),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.10), width: 0.45),
        ),
        child: Text(
          label,
          softWrap: true,
          style: TextStyle(
            fontSize: 10,
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _AnniversaryHorizontalScroller extends StatelessWidget {
  final Widget child;

  const _AnniversaryHorizontalScroller({required this.child});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: child,
    );
  }
}

class _AnniversaryEditSheet extends StatefulWidget {
  final Anniversary? editing;
  final AnniversaryType? fixedType;

  const _AnniversaryEditSheet({this.editing, this.fixedType});

  @override
  State<_AnniversaryEditSheet> createState() => _AnniversaryEditSheetState();
}

class _AnniversaryEditSheetState extends State<_AnniversaryEditSheet>
    with DateItemMutationState<_AnniversaryEditSheet> {
  late TextEditingController _title;
  late TextEditingController _desc;
  late DateTime _date;
  AnniversaryType _type = AnniversaryType.normal;
  AnniversaryCalendarType _cal = AnniversaryCalendarType.solar;
  int _colorValue = 0xFFE91E63;
  bool _remind = false;
  int _remindDays = 1;
  TimeOfDay _remindTime = const TimeOfDay(hour: 9, minute: 0);
  ReminderKind _reminderKind = ReminderKind.push;
  bool _ignoreYear = false;
  bool get _saving => dateItemBusy;
  DateItemActionOrigin? _origin;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _origin ??= DateItemActionOrigin.anniversary(context);
  }

  static const _presetColors = <int>[
    0xFFE91E63,
    0xFFFFA726,
    0xFF66BB6A,
    0xFF42A5F5,
    0xFF7E57C2,
    0xFF26A69A,
    0xFF8D6E63,
    0xFFEF5350,
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    _title = TextEditingController(text: e?.title ?? '');
    _desc = TextEditingController(text: e?.description ?? '');
    _date = e?.originDate ?? DateTime.now().add(const Duration(days: 1));
    _type = e?.type ?? widget.fixedType ?? AnniversaryType.memorial;
    _cal = e?.calendarType ?? AnniversaryCalendarType.solar;
    _colorValue = e?.colorValue ?? 0xFFE91E63;
    _remind = e?.remind ?? false;
    _remindDays = e?.remindDaysBefore ?? 1;
    _ignoreYear = e?.ignoreYear ?? false;
    _remindTime = TimeOfDay(
      hour: e?.remindHour ?? 9,
      minute: e?.remindMinute ?? 0,
    );
    _reminderKind = normalizeUserSelectableReminderKind(
      e?.reminderKind ?? ReminderKind.push,
    );
    if (_reminderKind == ReminderKind.off) {
      _remind = false;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  Anniversary _buildItem({required bool remind, required ReminderKind kind}) {
    return Anniversary.create(
      id: widget.editing?.id,
      title: _title.text.trim(),
      description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
      solarDate: _date,
      type: _type,
      calendarType: _cal,
      colorValue: _colorValue,
      isPinned: widget.editing?.isPinned ?? false,
      remind: remind,
      remindDaysBefore: _remindDays,
      remindHour: _remindTime.hour,
      remindMinute: _remindTime.minute,
      createdAt: widget.editing?.createdAt,
      reminderKind: remind ? kind : ReminderKind.off,
      ignoreYear: _type == AnniversaryType.birthday ? _ignoreYear : false,
    );
  }

  DateTime _remindAtFor(Anniversary item) {
    final nextDate = item.nextOccurrence;
    return DateTime(
      nextDate.year,
      nextDate.month,
      nextDate.day,
      item.remindHour,
      item.remindMinute,
    ).subtract(Duration(days: item.remindDaysBefore));
  }

  Future<_AnniversaryReminderPreflightResult> _checkReminderBeforeSave(
    Anniversary item,
    DateTime remindAt,
  ) async {
    final issueTitle = I18n.tr('anniversary.reminder.register_failed');
    try {
      switch (item.reminderKind) {
        case ReminderKind.push:
          final notificationService = context.read<NotificationService?>();
          final ready =
              await notificationService
                  ?.ensureReadyForReminder(
                    scheduledTime: remindAt,
                    issueTitle: issueTitle,
                    relatedId: item.id,
                  )
                  .timeout(
                    const Duration(seconds: 5),
                    onTimeout: () => false,
                  ) ??
              true;
          if (ready) return const _AnniversaryReminderPreflightResult.ok();
          final issue = notificationService?.lastScheduleIssue;
          return _AnniversaryReminderPreflightResult.disabled(
            () => issue?.copy == null
                ? I18n.tr('anniversary.reminder.not_registered')
                : issue!.renderMessage(),
          );
        case ReminderKind.popup:
          final notificationService = context.read<NotificationService?>();
          final ready =
              await notificationService
                  ?.ensureReadyForReminder(
                    scheduledTime: remindAt,
                    issueTitle: I18n.tr(
                      'anniversary.reminder.popup_fallback_failed',
                    ),
                    relatedId: item.id,
                  )
                  .timeout(
                    const Duration(seconds: 5),
                    onTimeout: () => false,
                  ) ??
              await LocalNotifications.instance.ensurePermission().timeout(
                const Duration(seconds: 5),
                onTimeout: () => false,
              );
          if (!ready) {
            final issue = notificationService?.lastScheduleIssue;
            return _AnniversaryReminderPreflightResult.disabled(
              () => issue?.copy == null
                  ? I18n.tr('anniversary.reminder.popup_permission_denied')
                  : '${I18n.tr('anniversary.reminder.popup_not_registered_prefix')}${issue!.renderMessage()}',
            );
          }
          return _AnniversaryReminderPreflightResult.warning(
            () => I18n.tr('anniversary.reminder.popup_warning'),
          );
        case ReminderKind.alarm:
          final notificationGranted = await LocalNotifications.instance
              .ensurePermission()
              .timeout(const Duration(seconds: 5), onTimeout: () => false);
          if (!notificationGranted) {
            return _AnniversaryReminderPreflightResult.disabled(
              () => I18n.tr('anniversary.reminder.alarm_permission_denied'),
            );
          }
          final warnings = <String>[];
          final channelIds = await AlarmService.instance
              .notificationChannelIds();
          if (channelIds != null &&
              channelIds.isNotEmpty &&
              !channelIds.contains(AlarmService.channelId)) {
            warnings.add('anniversary.reminder.alarm_channel_missing');
          }
          final exactGranted = await AlarmService.instance
              .hasExactAlarmPermission();
          if (!exactGranted) {
            warnings.add('anniversary.reminder.exact_alarm_missing');
          }
          final fullScreenGranted = await AlarmService.instance
              .hasFullScreenIntentPermission();
          if (!fullScreenGranted) {
            warnings.add('anniversary.reminder.fullscreen_missing');
          }
          if (warnings.isEmpty) {
            return const _AnniversaryReminderPreflightResult.ok();
          }
          return _AnniversaryReminderPreflightResult.warning(
            () => warnings
                .map(I18n.tr)
                .join(I18n.current == AppLocale.zh ? '；' : '; '),
          );
        case ReminderKind.email:
          return _AnniversaryReminderPreflightResult.warning(
            () => I18n.tr('anniversary.reminder.email_warning'),
          );
        case ReminderKind.off:
          return const _AnniversaryReminderPreflightResult.ok();
      }
    } catch (_) {
      return _AnniversaryReminderPreflightResult.disabled(
        () => I18n.tr('anniversary.reminder.not_registered'),
      );
    }
  }

  void _showSnackBarIfPossible(SnackBar snackBar) {
    if (Scaffold.maybeOf(context) == null) return;
    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }

  Future<void> _save() async {
    if (_saving) return;
    final origin = _origin!;
    if (!origin.isCurrent()) return;
    if (_title.text.trim().isEmpty) {
      _showSnackBarIfPossible(
        SnackBar(
          content: DateItemFeedbackText(
            () => I18n.tr('anniversary.validation.title_required'),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final item = _buildItem(remind: _remind, kind: _reminderKind);
    String Function()? reminderWarning;
    DateItemReminderIssue? syncIssue;
    await runDateItemMutation(
      origin: origin,
      failure: () => DateItemUiCopy.saveFailed,
      retry: _save,
      write: (operation) async {
        if (item.remind && !_remindAtFor(item).isAfter(DateTime.now())) {
          reminderWarning = () => I18n.tr('anniversary.reminder.time_past');
          item.remind = false;
          item.reminderKind = ReminderKind.off;
        }
        if (item.remind) {
          final preflight =
              await _checkReminderBeforeSave(item, _remindAtFor(item)).timeout(
                const Duration(seconds: 5),
                onTimeout: () => _AnniversaryReminderPreflightResult.disabled(
                  () => I18n.tr('anniversary.reminder.not_registered'),
                ),
              );
          if (!operation.isCurrent()) return;
          if (preflight.message.isNotEmpty) {
            reminderWarning = () =>
                '${I18n.tr('anniversary.reminder.saved_prefix')}${preflight.message}';
          }
          if (preflight.disableReminder) {
            item.remind = false;
            item.reminderKind = ReminderKind.off;
          }
        }
        if (!operation.isCurrent()) return;
        if (widget.editing == null) {
          await origin.anniversaries.add(item, canWrite: operation.isCurrent);
        } else {
          await origin.anniversaries.update(
            item,
            canWrite: operation.isCurrent,
          );
        }
        syncIssue = origin.anniversaries.lastReminderIssue;
      },
      onCommitted: () {
        final messenger = ScaffoldMessenger.maybeOf(context);
        final canShowSnackBar = Scaffold.maybeOf(context) != null;
        Navigator.pop(context);
        if (canShowSnackBar) {
          messenger?.showSnackBar(
            SnackBar(
              content: DateItemFeedbackText(
                () => syncIssue != null
                    ? DateItemUiCopy.savedReminderWarning
                    : reminderWarning?.call() ?? I18n.tr('anniversary.saved'),
              ),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      },
    );
  }

  Future<void> _delete() async {
    final editing = widget.editing;
    if (editing == null) return;
    await runDateItemMutation(
      origin: _origin!,
      failure: () => DateItemUiCopy.deleteFailed,
      confirm: (operation) => confirmDateItemDeletion(operation, editing.title),
      write: (operation) => _origin!.anniversaries.delete(
        editing.id,
        canWrite: operation.isCurrent,
      ),
      onCommitted: () => Navigator.pop(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lunar = LunarCalendar.fromSolar(_date);
    final cs = Theme.of(context).colorScheme;
    final fieldLabelStyle = appSecondaryControlLabelStyle(
      context,
    ).copyWith(color: cs.onSurfaceVariant.withValues(alpha: 0.72));
    final remindTimeText = I18nDateFormat.timeOfDay(
      hour: _remindTime.hour,
      minute: _remindTime.minute,
    );
    final isTypeLocked = widget.fixedType != null;
    final editorTitle = widget.editing == null
        ? _addTitleForType(_type)
        : _editTitleForType(_type);
    final titleHint = _titleHintForType(_type);

    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (context, controller) => AppSecondaryControlTheme(
        child: AppModalSheet(
          title: editorTitle,
          scrollController: controller,
          leadingActions: widget.editing == null
              ? const []
              : [
                  TextButton(
                    onPressed: _saving ? null : _delete,
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                    child: Text(I18n.tr('action.delete')),
                  ),
                ],
          actions: [
            TextButton(
              onPressed: () {
                if (_origin?.isCurrent() == true) Navigator.pop(context);
              },
              child: Text(I18n.tr('action.cancel')),
            ),
            FilledButton(
              key: const ValueKey('anniversary_editor_save_button'),
              onPressed: _saving ? null : _save,
              child: dateItemWriting
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      widget.editing == null
                          ? I18n.tr('action.add')
                          : I18n.tr('action.save'),
                    ),
            ),
          ],
          child: dateItemStatus(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  enabled: !_saving,
                  controller: _title,
                  autofocus: widget.editing == null,
                  decoration: InputDecoration(
                    labelText: I18n.tr('anniversary.field.title'),
                    hintText: titleHint,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  enabled: !_saving,
                  controller: _desc,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: I18n.tr('anniversary.field.description'),
                  ),
                ),
                const SizedBox(height: 16),
                if (!isTypeLocked) ...[
                  Text(
                    I18n.tr('anniversary.field.type'),
                    style: fieldLabelStyle,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: AnniversaryType.values
                        .where((t) {
                          return widget.editing != null ||
                              t != AnniversaryType.normal;
                        })
                        .map((t) {
                          final label = _typeLabelFor(t);
                          return ChoiceChip(
                            label: Text(label),
                            selected: _type == t,
                            onSelected: (_) => setState(() => _type = t),
                          );
                        })
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                ],
                Text(
                  I18n.tr('anniversary.field.date_type'),
                  style: fieldLabelStyle,
                ),
                const SizedBox(height: 6),
                _AnniversaryHorizontalScroller(
                  child: SegmentedButton<AnniversaryCalendarType>(
                    key: const ValueKey('anniversary_calendar_type_segments'),
                    segments: [
                      ButtonSegment(
                        value: AnniversaryCalendarType.solar,
                        icon: const Icon(Icons.wb_sunny_outlined),
                        label: Text(I18n.tr('calendar.solar')),
                      ),
                      ButtonSegment(
                        value: AnniversaryCalendarType.lunar,
                        icon: const Icon(Icons.nightlight_round),
                        label: Text(I18n.tr('calendar.lunar')),
                      ),
                    ],
                    selected: {_cal},
                    onSelectionChanged: (value) =>
                        setState(() => _cal = value.first),
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  key: const ValueKey('anniversary_editor_date_tile'),
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    _cal == AnniversaryCalendarType.solar
                        ? Icons.calendar_today_outlined
                        : Icons.nightlight_outlined,
                  ),
                  title: Text(
                    _cal == AnniversaryCalendarType.solar
                        ? '${I18n.tr('calendar.solar')} ${AppDateFormat.date(context, _date)}'
                        : '${I18n.tr('calendar.chinese_lunar_calendar')} ${_formatLunarDate(lunar)}',
                  ),
                  subtitle: Text(
                    _cal == AnniversaryCalendarType.solar
                        ? '${I18n.tr('calendar.corresponding_lunar')}: ${AlmanacLocaleFormat.formatFullLunarDate(lunar)}'
                        : '${I18n.tr('calendar.corresponding_solar')}: ${AppDateFormat.date(context, _date)}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final result = await AppDatePicker.show(
                      context,
                      initialDate: _date,
                      firstDate: DateTime(1900),
                      lastDate: DateTime(2099, 12, 31),
                      titleKey: 'anniversary.field.date_picker_title',
                      subtitleKey: 'anniversary.field.date_picker_subtitle',
                      initialMode: _cal == AnniversaryCalendarType.solar
                          ? AppDatePickerMode.solar
                          : AppDatePickerMode.lunar,
                      allowIgnoreYear: _type == AnniversaryType.birthday,
                      initialIgnoreYear: _ignoreYear,
                    );
                    if (!mounted) return;
                    if (result != null) {
                      setState(() {
                        _date = result.date;
                        _ignoreYear = result.ignoreYear;
                        _cal = result.mode == AppDatePickerMode.solar
                            ? AnniversaryCalendarType.solar
                            : AnniversaryCalendarType.lunar;
                      });
                    }
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  I18n.tr('anniversary.field.color'),
                  style: fieldLabelStyle,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  children: _presetColors.map((v) {
                    final selected = v == _colorValue;
                    return GestureDetector(
                      onTap: () => setState(() => _colorValue = v),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Color(v),
                          shape: BoxShape.circle,
                          border: selected
                              ? Border.all(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: 0.34),
                                  width: 0.45,
                                )
                              : null,
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _remind,
                  title: Text(
                    I18n.tr('countdown.field.due_reminder'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: _remind
                      ? Text(
                          '${I18n.tr('countdown.reminder.before_prefix')}$_remindDays${I18n.tr('countdown.reminder.before_suffix')} · $remindTimeText',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      : Text(
                          I18n.tr('countdown.reminder.closed'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                  onChanged: (v) => setState(() => _remind = v),
                ),
                if (_remind) ...[
                  AppSecondaryControlTheme(
                    child: _AnniversaryHorizontalScroller(
                      child: SegmentedButton<ReminderKind>(
                        key: const ValueKey(
                          'anniversary_reminder_kind_segments',
                        ),
                        segments: [
                          ButtonSegment(
                            value: ReminderKind.push,
                            icon: const Icon(Icons.notifications_outlined),
                            label: Text(I18n.tr('reminder.kind.push')),
                          ),
                          ButtonSegment(
                            value: ReminderKind.popup,
                            icon: const Icon(Icons.open_in_new_outlined),
                            label: Text(I18n.tr('reminder.kind.popup')),
                          ),
                          ButtonSegment(
                            value: ReminderKind.alarm,
                            icon: const Icon(Icons.alarm_outlined),
                            label: Text(I18n.tr('reminder.kind.alarm')),
                          ),
                          ButtonSegment(
                            value: ReminderKind.off,
                            icon: const Icon(Icons.notifications_off_outlined),
                            label: Text(I18n.tr('reminder.kind.off')),
                          ),
                        ],
                        selected: {_reminderKind},
                        onSelectionChanged: (selected) => setState(() {
                          _reminderKind = selected.first;
                          if (_reminderKind == ReminderKind.off) {
                            _remind = false;
                          }
                        }),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const SizedBox(width: 16),
                      Text('${I18n.tr('countdown.field.remind_days')}:'),
                      Expanded(
                        child: Slider(
                          value: _remindDays.toDouble(),
                          min: 0,
                          max: 30,
                          divisions: 30,
                          label: '$_remindDays',
                          onChanged: (v) =>
                              setState(() => _remindDays = v.toInt()),
                        ),
                      ),
                    ],
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.schedule),
                    title: Text(I18n.tr('countdown.field.remind_time')),
                    subtitle: Text(remindTimeText),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final picked = await AppTimePicker.show(
                        context,
                        initialTime: _remindTime,
                        title: I18n.tr('countdown.field.remind_time'),
                        minuteStep: 5,
                      );
                      if (!mounted) return;
                      if (picked != null) setState(() => _remindTime = picked);
                    },
                  ),
                ],
              ],
            ),
            showProgress: false,
          ),
        ),
      ),
    );
  }

  String _formatLunarDate(LunarDate lunar) =>
      AlmanacLocaleFormat.formatFullLunarDate(lunar, includeGanzhi: true);

  String _typeLabelFor(AnniversaryType type) {
    return switch (type) {
      AnniversaryType.normal => '⏰ ${I18n.tr('anniversary.countdown_short')}',
      AnniversaryType.birthday => '🎂 ${I18n.tr('anniversary.birthday')}',
      AnniversaryType.memorial => '💞 ${I18n.tr('anniversary.title')}',
      AnniversaryType.custom => '🔁 ${I18n.tr('anniversary.custom')}',
    };
  }

  String _addTitleForType(AnniversaryType type) {
    return switch (type) {
      AnniversaryType.birthday => _actionWithEntry('action.add', type),
      AnniversaryType.memorial => _actionWithEntry('action.add', type),
      AnniversaryType.normal => I18n.tr('countdown.editor.edit_title'),
      AnniversaryType.custom => I18n.tr('anniversary.editor.add_title'),
    };
  }

  String _editTitleForType(AnniversaryType type) {
    return switch (type) {
      AnniversaryType.birthday => _actionWithEntry('action.edit', type),
      AnniversaryType.memorial => _actionWithEntry('action.edit', type),
      AnniversaryType.normal => I18n.tr('countdown.editor.edit_title'),
      AnniversaryType.custom => I18n.tr('anniversary.editor.edit_title'),
    };
  }

  String _titleHintForType(AnniversaryType type) {
    return switch (type) {
      AnniversaryType.birthday => _entryWithTitle(type),
      AnniversaryType.memorial => _entryWithTitle(type),
      AnniversaryType.normal => I18n.tr('countdown.field.title'),
      AnniversaryType.custom => I18n.tr('anniversary.field.title_hint'),
    };
  }

  String _entryLabelFor(AnniversaryType type) {
    return switch (type) {
      AnniversaryType.normal => I18n.tr('anniversary.countdown_short'),
      AnniversaryType.birthday => I18n.tr('anniversary.birthday'),
      AnniversaryType.memorial => I18n.tr('anniversary.title'),
      AnniversaryType.custom => I18n.tr('anniversary.custom'),
    };
  }

  String _actionWithEntry(String actionKey, AnniversaryType type) {
    final action = I18n.tr(actionKey);
    final entry = _entryLabelFor(type);
    return I18n.current == AppLocale.en ? '$action $entry' : '$action$entry';
  }

  String _entryWithTitle(AnniversaryType type) {
    final entry = _entryLabelFor(type);
    final title = I18n.tr('anniversary.field.title');
    return I18n.current == AppLocale.en ? '$entry $title' : '$entry$title';
  }
}

class _AnniversaryReminderPreflightResult {
  final bool disableReminder;
  final String Function()? _resolve;
  String get message => _resolve?.call() ?? '';

  const _AnniversaryReminderPreflightResult._({
    required this.disableReminder,
    String Function()? resolve,
  }) : _resolve = resolve;
  const _AnniversaryReminderPreflightResult.ok()
    : this._(disableReminder: false);
  const _AnniversaryReminderPreflightResult.warning(String Function() resolve)
    : this._(disableReminder: false, resolve: resolve);
  const _AnniversaryReminderPreflightResult.disabled(String Function() resolve)
    : this._(disableReminder: true, resolve: resolve);
}
