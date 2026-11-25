import 'dart:io' show File;

import '../core/almanac_locale_format.dart';
import '../core/design_tokens.dart' show AppSurfaceStyle, DesignTokens;
import '../core/desktop_tokens.dart';
import '../desktop_web/desktop_embedded_scope.dart';
import '../core/image_decode_cache.dart';
import '../widgets/brand_background.dart';
import '../widgets/app_date_format.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import '../core/diary_insights.dart';
import '../core/heatmap_calendar.dart';
import '../core/i18n.dart';
import '../core/i18n_date_format.dart';
import '../core/recommended_goals_ui_copy.dart';
import '../models/diary_entry.dart';
import '../models/note.dart' show NoteBlock, NoteBlockType;
import '../providers/auth_provider.dart';
import '../providers/diary_provider.dart';
import '../core/lunar_calendar.dart';
import '../services/account_local_data_cleaner.dart';
import '../services/ai_service.dart';
import '../services/note_attachment_picker.dart';
import '../services/settings_action_origin.dart';
import '../widgets/app_date_picker.dart';
import '../widgets/empty_state.dart';
import '../widgets/mood_heatmap.dart';
import '../widgets/controller_dialog.dart' show createControllerDialogRoute;
import '../widgets/surface_components.dart';

Future<void> showDiaryEditor(
  BuildContext context, {
  DiaryEntry? entry,
  DateTime? initialDate,
}) {
  return Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => DiaryEditScreen(entry: entry, initialDate: initialDate),
    ),
  );
}

class DiaryScreen extends StatefulWidget implements LocaleStatePreservingRoute {
  final String? initialEntryId;

  const DiaryScreen({super.key, this.initialEntryId});

  @override
  State<DiaryScreen> createState() => _DiaryScreenState();
}

class _DiaryScreenState extends State<DiaryScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Mood? _moodFilter;
  Weather? _weatherFilter;
  String? _tagFilter;
  bool _markdownPreview = false;
  bool _showFilters = false;
  String? _highlightedEntryId;
  String? _scrolledEntryId;
  final Map<String, GlobalKey> _entryKeys = <String, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    _highlightedEntryId = widget.initialEntryId;
    I18n.localeListenable.addListener(_onLocaleChanged);
  }

  @override
  void didUpdateWidget(covariant DiaryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialEntryId != widget.initialEntryId) {
      _highlightedEntryId = widget.initialEntryId;
      _scrolledEntryId = null;
      if (_highlightedEntryId != null) {
        _searchQuery = '';
        _searchController.clear();
        _moodFilter = null;
        _weatherFilter = null;
        _tagFilter = null;
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

  GlobalKey _keyForEntry(String id) =>
      _entryKeys.putIfAbsent(id, () => GlobalKey());

  void _scheduleScrollToHighlighted(List<DiaryEntry> filtered) {
    final targetId = _highlightedEntryId;
    if (targetId == null ||
        targetId.isEmpty ||
        _scrolledEntryId == targetId) {
      return;
    }
    final targetIndex = filtered.indexWhere((e) => e.id == targetId);
    if (targetIndex < 0) return;
    _scrolledEntryId = targetId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _entryKeys[targetId]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
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

  int? _filterEntriesFingerprint;
  String? _filterQueryCached;
  Mood? _filterMoodCached;
  Weather? _filterWeatherCached;
  String? _filterTagCached;
  AppLocale? _filterLocaleCached;
  List<DiaryEntry>? _filteredEntriesCached;

  int? _tagsEntriesFingerprint;
  List<String>? _sortedTagsCached;

  int _entriesFingerprint(List<DiaryEntry> entries) {
    var fp = entries.length;
    for (final e in entries) {
      fp = Object.hash(
        fp,
        e.id,
        e.updatedAt.millisecondsSinceEpoch,
        e.mood?.index ?? -1,
        e.weather?.index ?? -1,
        e.tags.length,
      );
    }
    return fp;
  }

  List<String> _sortedTagsFor(List<DiaryEntry> allEntries, int entriesFp) {
    final cached = _sortedTagsCached;
    if (cached != null && _tagsEntriesFingerprint == entriesFp) {
      return cached;
    }
    final tags = <String>{
      for (final e in allEntries) ...e.tags,
    }.toList()..sort();
    final immutable = List<String>.unmodifiable(tags);
    _tagsEntriesFingerprint = entriesFp;
    _sortedTagsCached = immutable;
    return immutable;
  }

  List<DiaryEntry> _applyFilters(
    List<DiaryEntry> allEntries,
    AppLocale locale, {
    int? entriesFp,
  }) {
    final fp = entriesFp ?? _entriesFingerprint(allEntries);
    final query = _searchQuery.trim().toLowerCase();
    final cached = _filteredEntriesCached;
    if (cached != null &&
        _filterEntriesFingerprint == fp &&
        _filterQueryCached == query &&
        _filterMoodCached == _moodFilter &&
        _filterWeatherCached == _weatherFilter &&
        _filterTagCached == _tagFilter &&
        _filterLocaleCached == locale) {
      return cached;
    }
    final result = List<DiaryEntry>.unmodifiable(
      allEntries.where((entry) {
        if (_moodFilter != null && entry.mood != _moodFilter) return false;
        if (_weatherFilter != null && entry.weather != _weatherFilter) {
          return false;
        }
        if (_tagFilter != null && !entry.tags.contains(_tagFilter)) {
          return false;
        }
        if (query.isEmpty) return true;
        if (entry.content.toLowerCase().contains(query)) return true;
        if (entry.titleFor(locale).toLowerCase().contains(query)) return true;
        if ((entry.location ?? '').toLowerCase().contains(query)) return true;
        if (entry.tags.any((t) => t.toLowerCase().contains(query))) return true;
        return false;
      }),
    );
    _filterEntriesFingerprint = fp;
    _filterQueryCached = query;
    _filterMoodCached = _moodFilter;
    _filterWeatherCached = _weatherFilter;
    _filterTagCached = _tagFilter;
    _filterLocaleCached = locale;
    _filteredEntriesCached = result;
    return result;
  }

  bool get _hasActiveFilters =>
      _searchQuery.trim().isNotEmpty ||
      _moodFilter != null ||
      _weatherFilter != null ||
      _tagFilter != null;

  @override
  Widget build(BuildContext context) {
    return _buildContent(context, I18n.current);
  }

  Widget _buildContent(BuildContext context, [AppLocale? initialLocale]) {
    final locale = initialLocale ?? I18n.current;
    final isEn = locale == AppLocale.en;
    final provider = context.watch<DiaryProvider>();
    final entries = provider.entries;
    final entriesFp = _entriesFingerprint(entries);
    final filtered = _applyFilters(entries, locale, entriesFp: entriesFp);
    final insights = DiaryInsightEngine.buildInsights(entries, locale: locale);
    _scheduleScrollToHighlighted(filtered);
    final theme = Theme.of(context);
    final surfaceStyle = appSurfaceStyleOf(context);
    final isLiquidGlass = surfaceStyle == AppSurfaceStyle.liquidGlass;
    final hasInsights = insights.isNotEmpty;
    final headerCount = 3 + (hasInsights ? 1 : 0);

    final scaffold = Scaffold(
      backgroundColor: isLiquidGlass ? Colors.transparent : null,
      appBar: AppBar(
        title: Text(I18n.tr('diary.title')),
        actions: [
          IconButton(
            icon: const Icon(Icons.insights),
            tooltip: I18n.tr('diary.stats.tooltip'),
            onPressed: () => _showMoodStats(context, provider),
          ),
          IconButton(
            icon: const Icon(Icons.auto_awesome_outlined),
            tooltip: I18n.tr('diary.ai.deep_review.tooltip'),
            onPressed: entries.isEmpty
                ? null
                : () => _runDeepDiaryReview(context, entries),
          ),
        ],
      ),
      body: entries.isEmpty
          ? EmptyState(
              icon: Icons.book_outlined,
              message: I18n.tr('diary.empty.message'),
              actionLabel: I18n.tr('diary.write'),
              onAction: () => _openEdit(context),
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: DesktopTokens.secondaryMaxContentWidth,
                ),
                child: ListView.builder(
                  controller: _scrollController,
                  // 底部 padding 计入 Android 手势条 inset + FAB 余量，
                  // 避免“写日记”按钮滚动到底时压住最后一张日记卡。
                  padding: EdgeInsets.fromLTRB(
                    12,
                    12,
                    12,
                    MediaQuery.paddingOf(context).bottom + 88,
                  ),
                  // 虚拟化：摘要卡、筛选栏、（可选）洞察卡与列表头，
                  // 其余索引按过滤后 entries 懒构建卡片，避免全量构建。
                  itemCount:
                      headerCount + (filtered.isEmpty ? 1 : filtered.length),
                  itemBuilder: (context, index) {
                    if (index == 0) return _buildSummaryCard(context, provider);
                    if (index == 1) {
                      return _buildSearchAndFilterPanel(
                        context,
                        entries,
                        isEn,
                      );
                    }
                    if (hasInsights && index == 2) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: _DiaryInsightCard(insights: insights),
                      );
                    }
                    if (index == headerCount - 1) {
                      return _buildRecentHeader(filtered.length);
                    }
                    if (filtered.isEmpty) {
                      return _buildNoFilterMatches(context, isEn);
                    }
                    final entry = filtered[index - headerCount];
                    return KeyedSubtree(
                      key: _keyForEntry(entry.id),
                      child: _DiaryCard(
                        entry: entry,
                        highlighted: entry.id == _highlightedEntryId,
                        markdownPreview: _markdownPreview,
                      ),
                    );
                  },
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'diary_write_fab',
        onPressed: () => _openEdit(context),
        icon: const Icon(Icons.edit_note),
        label: Text(I18n.tr('diary.write')),
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
      color: theme.scaffoldBackgroundColor,
      child: BrandBackground(child: scaffold),
    );
  }

  Widget _buildSearchAndFilterPanel(
    BuildContext context,
    List<DiaryEntry> allEntries,
    bool isEn,
  ) {
    final cs = Theme.of(context).colorScheme;
    final tags = _sortedTagsFor(allEntries, _entriesFingerprint(allEntries));

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('diary_search_field'),
                  controller: _searchController,
                  onChanged: (value) => setState(() => _searchQuery = value),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: isEn
                        ? 'Search diary content, location or #tag...'
                        : '搜索日记正文、地点或 #标签...',
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
                      vertical: 9,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        appSurfaceStyleOf(context)?.smallTileRadius ??
                            DesignTokens.radiusControl,
                      ),
                      borderSide: BorderSide(
                        color: cs.outlineVariant,
                        width: 0.45,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        appSurfaceStyleOf(context)?.smallTileRadius ??
                            DesignTokens.radiusControl,
                      ),
                      borderSide: BorderSide(
                        color: cs.outlineVariant,
                        width: 0.45,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                key: const ValueKey('diary_markdown_preview_toggle'),
                label: Text(
                  'MD',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.normal,
                  ),
                ),
                tooltip: isEn ? 'Toggle Markdown preview' : '切换 Markdown 预览',
                selected: _markdownPreview,
                onSelected: (selected) =>
                    setState(() => _markdownPreview = selected),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                key: const ValueKey('diary_filter_expand_toggle'),
                label: Icon(
                  Icons.tune_rounded,
                  size: 16,
                  color: (_showFilters || _hasActiveFilters)
                      ? cs.primary
                      : cs.onSurfaceVariant,
                ),
                tooltip: isEn
                    ? 'Mood, weather & tag filters'
                    : '心情 / 天气 / 标签筛选',
                selected: _showFilters || _hasActiveFilters,
                onSelected: (selected) =>
                    setState(() => _showFilters = selected),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
          if (_showFilters || _hasActiveFilters) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (_hasActiveFilters) ...[
                    ActionChip(
                      key: const ValueKey('diary_clear_filters_btn'),
                      label: Text(
                        isEn ? 'Clear' : '重置',
                        style: const TextStyle(fontSize: 12),
                      ),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchQuery = '';
                          _moodFilter = null;
                          _weatherFilter = null;
                          _tagFilter = null;
                        });
                      },
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    const SizedBox(width: 6),
                  ],
                  for (final m in Mood.values) ...[
                    ChoiceChip(
                      key: ValueKey('diary_mood_filter_${m.name}'),
                      label: Text(
                        '${m.emoji} ${_moodLabel(m)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      selected: _moodFilter == m,
                      onSelected: (_) => setState(
                        () => _moodFilter = _moodFilter == m ? null : m,
                      ),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    const SizedBox(width: 6),
                  ],
                  for (final w in Weather.values) ...[
                    ChoiceChip(
                      key: ValueKey('diary_weather_filter_${w.name}'),
                      label: Text(
                        '${w.emoji} ${_weatherLabel(w)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      selected: _weatherFilter == w,
                      onSelected: (_) => setState(
                        () => _weatherFilter = _weatherFilter == w ? null : w,
                      ),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    const SizedBox(width: 6),
                  ],
                  for (final t in tags) ...[
                    ChoiceChip(
                      key: ValueKey('diary_tag_filter_$t'),
                      label: Text('#$t', style: const TextStyle(fontSize: 12)),
                      selected: _tagFilter == t,
                      onSelected: (_) => setState(
                        () => _tagFilter = _tagFilter == t ? null : t,
                      ),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNoFilterMatches(BuildContext context, bool isEn) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.filter_alt_off_outlined, size: 34, color: cs.outline),
          const SizedBox(height: 8),
          Text(
            isEn ? 'No matching diary entries' : '没有符合条件的日记',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () {
              _searchController.clear();
              setState(() {
                _searchQuery = '';
                _moodFilter = null;
                _weatherFilter = null;
                _tagFilter = null;
              });
            },
            child: Text(isEn ? 'Reset filters' : '重置筛选'),
          ),
        ],
      ),
    );
  }

  /// 摘要头卡：统计行 + 心情热力图。
  Widget _buildSummaryCard(BuildContext context, DiaryProvider provider) {
    return AppSurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(
            title: I18n.tr('diary.summary.title'),
            subtitle: I18n.tr('diary.summary.subtitle'),
            padding: EdgeInsets.zero,
          ),
          const SizedBox(height: 12),
          _buildSummaryMetrics(context, provider),
          const SizedBox(height: 16),
          MoodHeatmap(
            entriesByDate: provider.entriesByDate,
            onOpenDay: (date) => _openEdit(
              context,
              entry:
                  provider.entriesByDate[HeatmapCalendarWindow.dateKey(date)],
              date: date,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryMetrics(BuildContext context, DiaryProvider provider) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final totalTitle = I18n.tr('diary.summary.total');
    final totalValue = _formatDiaryEntryCount(provider.totalCount);
    final monthTitle = I18n.tr('diary.summary.this_month');
    final monthValue = _formatDiaryEntryCount(provider.thisMonthCount);
    final streakTitle = I18n.tr('diary.summary.streak');
    final streakValue = _formatDiaryStreak(provider.currentStreak);

    final valueStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.normal,
      fontFeatures: const [FontFeature.tabularFigures()],
      color: cs.onSurface,
    );
    final titleStyle = theme.textTheme.bodySmall?.copyWith(
      color: cs.onSurface.withValues(alpha: 0.62),
      fontWeight: FontWeight.normal,
    );

    final metrics = [
      (
        title: totalTitle,
        value: totalValue,
        icon: Icons.book_outlined,
        color: cs.primary,
      ),
      (
        title: monthTitle,
        value: monthValue,
        icon: Icons.calendar_month,
        color: cs.secondary,
      ),
      (
        title: streakTitle,
        value: streakValue,
        icon: Icons.bolt,
        color: cs.tertiary,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final useCompact =
            availableWidth.isFinite &&
            _fitsCompactSummary(
              context: context,
              availableWidth: availableWidth,
              metrics: metrics,
              valueStyle: valueStyle,
              titleStyle: titleStyle,
            );

        if (useCompact) {
          return Row(
            children: [
              Expanded(
                child: _stat(
                  context,
                  totalTitle,
                  totalValue,
                  Icons.book_outlined,
                  cs.primary,
                ),
              ),
              _metricDivider(cs),
              Expanded(
                child: _stat(
                  context,
                  monthTitle,
                  monthValue,
                  Icons.calendar_month,
                  cs.secondary,
                ),
              ),
              _metricDivider(cs),
              Expanded(
                child: _stat(
                  context,
                  streakTitle,
                  streakValue,
                  Icons.bolt,
                  cs.tertiary,
                ),
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < metrics.length; i++) ...[
              if (i > 0) _horizontalMetricDivider(cs),
              _stat(
                context,
                metrics[i].title,
                metrics[i].value,
                metrics[i].icon,
                metrics[i].color,
                fullWidth: true,
              ),
            ],
          ],
        );
      },
    );
  }

  bool _fitsCompactSummary({
    required BuildContext context,
    required double availableWidth,
    required List<
      ({
        Color color,
        IconData icon,
        String title,
        String value,
      })
    > metrics,
    required TextStyle? valueStyle,
    required TextStyle? titleStyle,
  }) {
    // 3 columns and 2 dividers of width 1 + margin 12*2 = 50.0 total
    final colWidth = (availableWidth - 50.0) / 3;
    if (colWidth <= 0) return false;

    final textScaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);

    for (final m in metrics) {
      if (_hasWordExceedingWidth(
        m.value,
        valueStyle,
        textScaler,
        direction,
        colWidth,
      )) {
        return false;
      }
      if (_hasWordExceedingWidth(
        m.title,
        titleStyle,
        textScaler,
        direction,
        colWidth,
      )) {
        return false;
      }
      if (_textExceedsWidth(
        m.value,
        valueStyle,
        textScaler,
        direction,
        colWidth,
      )) {
        return false;
      }
      if (_textExceedsWidth(
        m.title,
        titleStyle,
        textScaler,
        direction,
        colWidth,
      )) {
        return false;
      }
    }
    return true;
  }

  bool _hasWordExceedingWidth(
    String text,
    TextStyle? style,
    TextScaler textScaler,
    TextDirection direction,
    double maxWidth,
  ) {
    final tokens = RegExp(r'[A-Za-z0-9%+.,−-]+|[^\x00-\x7F]').allMatches(text);
    for (final match in tokens) {
      final token = match.group(0)!;
      final painter = TextPainter(
        text: TextSpan(text: token, style: style),
        textScaler: textScaler,
        textDirection: direction,
      )..layout();
      final width = painter.width;
      painter.dispose();
      if (width > maxWidth) {
        return true;
      }
    }
    return false;
  }

  bool _textExceedsWidth(
    String text,
    TextStyle? style,
    TextScaler textScaler,
    TextDirection direction,
    double maxWidth,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textScaler: textScaler,
      textDirection: direction,
    )..layout();
    final exceeds = painter.width > maxWidth;
    painter.dispose();
    return exceeds;
  }

  /// "最近日记"列表头（含条目数）。
  Widget _buildRecentHeader(int count) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: AppSectionHeader(
        title: I18n.tr('diary.recent.title'),
        subtitle: _formatDiaryRecentSubtitle(count),
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      ),
    );
  }

  Widget _stat(
    BuildContext context,
    String title,
    String value,
    IconData icon,
    Color color, {
    bool fullWidth = false,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final surfaceStyle = appSurfaceStyleOf(context);
    final iconBox = Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(
          surfaceStyle?.smallTileRadius ?? DesignTokens.radiusControl,
        ),
      ),
      child: Icon(icon, color: color, size: 17),
    );
    final valueText = Text(
      value,
      style: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.normal,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: cs.onSurface,
      ),
    );
    final titleText = Text(
      title,
      style: theme.textTheme.bodySmall?.copyWith(
        color: cs.onSurface.withValues(alpha: 0.62),
        fontWeight: FontWeight.normal,
      ),
    );

    if (fullWidth) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          iconBox,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                valueText,
                const SizedBox(height: 2),
                titleText,
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        iconBox,
        const SizedBox(height: 10),
        valueText,
        const SizedBox(height: 2),
        titleText,
      ],
    );
  }

  Widget _metricDivider(ColorScheme cs) {
    return Container(
      width: 1,
      height: 42,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: cs.outlineVariant.withValues(alpha: 0.55),
    );
  }

  Widget _horizontalMetricDivider(ColorScheme cs) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: 10),
      color: cs.outlineVariant.withValues(alpha: 0.55),
    );
  }

  void _openEdit(BuildContext context, {DiaryEntry? entry, DateTime? date}) {
    showDiaryEditor(context, entry: entry, initialDate: date);
  }

  void _showMoodStats(BuildContext context, DiaryProvider p) {
    final dist = p.moodDistribution(days: 30);
    final total = dist.values.fold(0, (s, v) => s + v);
    showAppModalSheet(
      context: context,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final cs = theme.colorScheme;
        final isDark = theme.brightness == Brightness.dark;
        return AppModalSheet(
          title: I18n.tr('diary.mood.stats.title'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (total == 0)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text(I18n.tr('diary.no_data'))),
                )
              else
                ...Mood.values.map((m) {
                  final c = dist[m] ?? 0;
                  final pct = total == 0 ? 0.0 : c / total;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 52,
                          child: Text(
                            '${m.emoji} ${_moodLabel(m)}',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                              DesignTokens.radiusXs,
                            ),
                            child: LinearProgressIndicator(
                              value: pct,
                              minHeight: 10,
                              backgroundColor: cs.surfaceContainerHighest
                                  .withValues(alpha: isDark ? 0.12 : 0.22),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 40,
                          child: Text(
                            _formatDiaryEntryCount(c),
                            textAlign: TextAlign.end,
                            style: TextStyle(
                              fontSize: 12,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                              color: cs.onSurface.withValues(alpha: 0.55),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  Future<void> _runDeepDiaryReview(
    BuildContext context,
    List<DiaryEntry> entries,
  ) async {
    final ai = context.read<AiService>();
    if (!ai.enabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(I18n.tr('diary.ai.disabled')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    var dialogOpen = false;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    dialogOpen = true;
    try {
      final review = await ai.deepDiaryReview(entries: entries);
      if (!context.mounted) return;
      if (dialogOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogOpen = false;
      }
      final route = createControllerDialogRoute<void>(
        context: context,
        builder: (dialogContext) => ValueListenableBuilder<AppLocale>(
          valueListenable: I18n.localeListenable,
          builder: (dialogContext, _, _) => AppDialog(
            title: Text(I18n.tr('diary.ai.deep_review.title')),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560, maxHeight: 520),
              child: SingleChildScrollView(
                child: SelectableText(
                  review,
                  style: const TextStyle(height: 1.45),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(I18n.tr('action.close')),
              ),
            ],
          ),
        ),
      );
      await Navigator.of(context, rootNavigator: true).push<void>(route);
    } on AiException catch (e) {
      if (!context.mounted) return;
      if (dialogOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogOpen = false;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${I18n.tr('diary.ai.review_failed_prefix')}${e.message}',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      if (dialogOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogOpen = false;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${I18n.tr('diary.ai.review_failed_prefix')}$e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

String _formatDiaryEntryCount(int count) {
  final suffixKey = count == 1
      ? 'diary.entry.count_suffix_singular'
      : 'diary.entry.count_suffix';
  return '$count${I18n.tr(suffixKey)}';
}

String _formatDiaryStreak(int count) {
  final unitKey = count == 1 ? 'diary.streak.day_singular' : 'unit.day';
  return '$count ${I18n.tr(unitKey)}';
}

String _formatDiaryRecentSubtitle(int count) {
  final suffixKey = count == 1
      ? 'diary.recent.records_suffix_singular'
      : 'diary.recent.records_suffix';
  return '$count${I18n.tr(suffixKey)}';
}

class _DiaryInsightCard extends StatelessWidget {
  final List<DiaryInsight> insights;

  const _DiaryInsightCard({required this.insights});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return AppSurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.psychology_alt_outlined, color: cs.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  I18n.tr('diary.ai.insights'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final insight in insights)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _insightIcon(insight.kind),
                    size: 16,
                    color: appReadableForeground(
                      cs.surface,
                      _insightColor(cs, insight.kind, isDark: isDark),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          insight.title,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          insight.message,
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurface.withValues(alpha: 0.62),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  IconData _insightIcon(DiaryInsightKind kind) => switch (kind) {
    DiaryInsightKind.overview => Icons.auto_graph_outlined,
    DiaryInsightKind.emotionTrend => Icons.trending_up,
    DiaryInsightKind.theme => Icons.sell_outlined,
    DiaryInsightKind.streak => Icons.local_fire_department_outlined,
    DiaryInsightKind.attention => Icons.health_and_safety_outlined,
  };

  Color _insightColor(
    ColorScheme cs,
    DiaryInsightKind kind, {
    required bool isDark,
  }) => switch (kind) {
    DiaryInsightKind.overview => cs.primary,
    DiaryInsightKind.emotionTrend =>
      isDark ? const Color(0xFF66BB6A) : DesignTokens.defaultSuccess,
    DiaryInsightKind.theme => cs.tertiary,
    DiaryInsightKind.streak =>
      isDark ? const Color(0xFFFFB74D) : DesignTokens.defaultWarning,
    DiaryInsightKind.attention => cs.error,
  };
}

class _DiaryCard extends StatelessWidget {
  final DiaryEntry entry;
  final bool highlighted;
  final bool markdownPreview;

  const _DiaryCard({
    required this.entry,
    this.highlighted = false,
    this.markdownPreview = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final surfaceStyle = appSurfaceStyleOf(context);
    final lunar = LunarCalendar.fromSolar(entry.date);
    final accent = _moodColor(entry.mood, cs, isDark: isDark);
    final cardBg = Color.alphaBlend(
      surfaceStyle?.cardFillColor ?? cs.surface,
      theme.scaffoldBackgroundColor,
    );
    final badgeBg = Color.alphaBlend(accent.withValues(alpha: 0.1), cardBg);
    final readableAccent = appReadableForeground(badgeBg, accent);
    final readableLunarColor = appReadableForeground(
      badgeBg,
      readableAccent.withValues(alpha: 0.85),
    );

    final dateBadge = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(
          surfaceStyle?.smallTileRadius ?? DesignTokens.radiusControl,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${entry.date.month}/${entry.date.day}',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.normal,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: readableAccent,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            AlmanacLocaleFormat.formatLunarDay(lunar),
            style: TextStyle(
              fontSize: 10,
              color: readableLunarColor,
            ),
          ),
        ],
      ),
    );

    final titleWidget = Text(
      entry.title,
      style: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.normal,
        color: cs.onSurface,
      ),
    );

    return AppSurfaceCard(
      key: ValueKey('diary_card_${entry.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      border: highlighted
          ? Border.all(color: cs.primary, width: 0.6)
          : null,
      onTap: () => showDiaryEditor(context, entry: entry),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 98,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final availableWidth = constraints.maxWidth;
                    final textScaler = MediaQuery.textScalerOf(context);
                    final textDirection = Directionality.of(context);
                    final locale = Localizations.maybeLocaleOf(context);

                    double measureText(String text, TextStyle style) {
                      final painter = TextPainter(
                        text: TextSpan(text: text, style: style),
                        textScaler: textScaler,
                        textDirection: textDirection,
                        locale: locale,
                      )..layout();
                      final width = painter.width;
                      painter.dispose();
                      return width;
                    }

                    final dateStr = '${entry.date.month}/${entry.date.day}';
                    final lunarStr = AlmanacLocaleFormat.formatLunarDay(lunar);
                    final dateWidth =
                        measureText(dateStr, const TextStyle(fontSize: 15));
                    final lunarWidth =
                        measureText(lunarStr, const TextStyle(fontSize: 10));
                    final badgeWidth =
                        (dateWidth > lunarWidth ? dateWidth : lunarWidth) +
                        20.0;
                    final sideColWidth = availableWidth.isFinite
                        ? (availableWidth - badgeWidth - 10.0)
                        : 0.0;

                    final titleStyle = theme.textTheme.titleMedium ??
                        const TextStyle(fontSize: 16);
                    double maxTokenWidth = 0.0;
                    for (final match in RegExp(r'[A-Za-z0-9%+.,−-]+').allMatches(entry.title)) {
                      final w = measureText(match.group(0)!, titleStyle);
                      if (w > maxTokenWidth) maxTokenWidth = w;
                    }

                    final bool shouldReflow = !availableWidth.isFinite ||
                        sideColWidth < 200.0 ||
                        maxTokenWidth > sideColWidth;

                    if (shouldReflow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              dateBadge,
                              const SizedBox(width: 10),
                              Expanded(
                                child: _buildCardMetadata(context, cs, accent),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          titleWidget,
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        dateBadge,
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildCardMetadata(context, cs, accent),
                              const SizedBox(height: 8),
                              titleWidget,
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
                if (entry.preview.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  if (markdownPreview)
                    _DiaryMarkdownBody(content: entry.content, compact: true)
                  else
                    Text(
                      entry.preview,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.72),
                        height: 1.55,
                      ),
                    ),
                ],
                if (entry.imagePaths.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 54,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final path in entry.imagePaths) ...[
                            _DiaryImageThumb(path: path, size: 54),
                            const SizedBox(width: 6),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
                if ((entry.location ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 13,
                        color: cs.primary,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          entry.location!.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurface.withValues(alpha: 0.72),
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (entry.tags.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: entry.tags
                        .map(
                          (t) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest.withValues(
                                alpha: 0.75,
                              ),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '#$t',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurface.withValues(alpha: 0.7),
                                fontWeight: FontWeight.normal,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardMetadata(
    BuildContext context,
    ColorScheme cs,
    Color accent,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final timeStr = I18nDateFormat.time(entry.updatedAt);
        final defaultTextStyle = DefaultTextStyle.of(context);
        final isBold = MediaQuery.boldTextOf(context);

        TextStyle resolveEffectiveTextStyle(TextStyle style) {
          var effective =
              style.inherit ? defaultTextStyle.style.merge(style) : style;
          if (isBold) {
            effective = effective.merge(
              const TextStyle(fontWeight: FontWeight.bold),
            );
          }
          return effective;
        }

        final timeStyle = TextStyle(
          fontSize: 11,
          color: cs.onSurface.withValues(alpha: 0.5),
        );
        final effectiveTimeStyle = resolveEffectiveTextStyle(timeStyle);

        final badgeStyle = TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.normal,
          color: cs.onSurface.withValues(alpha: 0.68),
        );
        final effectiveBadgeStyle = resolveEffectiveTextStyle(badgeStyle);

        final textScaler = MediaQuery.textScalerOf(context);
        final textDirection = Directionality.of(context);
        final locale = Localizations.maybeLocaleOf(context);

        double measureText(String text, TextStyle style) {
          final painter = TextPainter(
            text: TextSpan(text: text, style: style),
            textScaler: textScaler,
            textDirection: textDirection,
            locale: locale,
          )..layout();
          final width = painter.width;
          painter.dispose();
          return width;
        }

        final timeWidth = measureText(timeStr, effectiveTimeStyle);
        double badgesWidth = 0.0;
        int badgeCount = 0;
        if (entry.mood != null) {
          badgesWidth +=
              measureText(entry.mood!.emoji, effectiveBadgeStyle) + 16.0;
          badgeCount++;
        }
        if (entry.weather != null) {
          badgesWidth +=
              measureText(entry.weather!.emoji, effectiveBadgeStyle) + 16.0;
          badgeCount++;
        }
        if (badgeCount > 1) {
          badgesWidth += (badgeCount - 1) * 6.0;
        }

        final requiredWidth = badgesWidth + timeWidth;
        final fitsSingleRow =
            availableWidth.isFinite && requiredWidth <= availableWidth;

        if (!availableWidth.isFinite) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (entry.mood != null)
                _DiaryBadge(label: entry.mood!.emoji, color: accent),
              if (entry.weather != null) ...[
                if (entry.mood != null) const SizedBox(width: 6),
                _DiaryBadge(label: entry.weather!.emoji, color: cs.primary),
              ],
              if (badgeCount > 0) const SizedBox(width: 8),
              Text(timeStr, maxLines: 1, style: timeStyle),
            ],
          );
        }

        if (fitsSingleRow) {
          return Row(
            children: [
              if (entry.mood != null)
                _DiaryBadge(label: entry.mood!.emoji, color: accent),
              if (entry.weather != null) ...[
                if (entry.mood != null) const SizedBox(width: 6),
                _DiaryBadge(label: entry.weather!.emoji, color: cs.primary),
              ],
              const Spacer(),
              Text(timeStr, maxLines: 1, style: timeStyle),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (badgeCount > 0) ...[
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (entry.mood != null)
                    _DiaryBadge(label: entry.mood!.emoji, color: accent),
                  if (entry.weather != null)
                    _DiaryBadge(label: entry.weather!.emoji, color: cs.primary),
                ],
              ),
              const SizedBox(height: 4),
            ],
            Text(timeStr, maxLines: 1, style: timeStyle),
          ],
        );
      },
    );
  }
}

class _DiaryBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _DiaryBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.normal,
          color: cs.onSurface.withValues(alpha: 0.68),
        ),
      ),
    );
  }
}

Color _moodColor(Mood? mood, ColorScheme cs, {bool isDark = false}) {
  switch (mood) {
    case Mood.awesome:
      return isDark ? const Color(0xFF66BB6A) : DesignTokens.defaultSuccess;
    case Mood.good:
      return cs.primary;
    case Mood.okay:
      return cs.onSurfaceVariant;
    case Mood.bad:
      return isDark ? const Color(0xFFFFB74D) : DesignTokens.defaultWarning;
    case Mood.terrible:
      return cs.error;
    case null:
      return cs.primary;
  }
}

String _moodLabel(Mood mood) => switch (mood) {
  Mood.awesome => I18n.tr('diary.mood.awesome'),
  Mood.good => I18n.tr('diary.mood.good'),
  Mood.okay => I18n.tr('diary.mood.okay'),
  Mood.bad => I18n.tr('diary.mood.bad'),
  Mood.terrible => I18n.tr('diary.mood.terrible'),
};

String _weatherLabel(Weather weather) => switch (weather) {
  Weather.sunny => I18n.tr('diary.weather.sunny'),
  Weather.cloudy => I18n.tr('diary.weather.cloudy'),
  Weather.overcast => I18n.tr('diary.weather.overcast'),
  Weather.rain => I18n.tr('diary.weather.rain'),
  Weather.snow => I18n.tr('diary.weather.snow'),
  Weather.wind => I18n.tr('diary.weather.wind'),
  Weather.fog => I18n.tr('diary.weather.fog'),
  Weather.thunder => I18n.tr('diary.weather.thunder'),
};

class _DiaryEditorOrigin {
  _DiaryEditorOrigin(this.context)
      : authority = SettingsActionOrigin(context),
        diary = context.read<DiaryProvider>(),
        auth = context.read<AuthProvider?>(),
        accountGeneration = AccountLocalDataCleaner.accountDataGeneration,
        route = ModalRoute.of(context);

  final BuildContext context;
  final SettingsActionOrigin authority;
  final DiaryProvider diary;
  final AuthProvider? auth;
  final int accountGeneration;
  final ModalRoute<dynamic>? route;

  bool isCurrent({bool checkRoute = true}) {
    if (!context.mounted) return false;
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
      accountGeneration,
    )) {
      return false;
    }
    if (!authority.isCurrent(checkRoute: checkRoute)) return false;
    try {
      if (!identical(context.read<DiaryProvider>(), diary)) return false;
      if (!identical(context.read<AuthProvider?>(), auth)) return false;
      return true;
    } catch (_) {
      return false;
    }
  }
}

class DiaryEditScreen extends StatefulWidget
    implements LocaleStatePreservingRoute {
  final DiaryEntry? entry;
  final DateTime? initialDate;
  const DiaryEditScreen({super.key, this.entry, this.initialDate});

  @override
  State<DiaryEditScreen> createState() => _DiaryEditScreenState();
}

class _DiaryEditScreenState extends State<DiaryEditScreen> {
  late TextEditingController _content;
  late TextEditingController _tag;
  late TextEditingController _location;
  late DateTime _date;
  Mood? _mood;
  Weather? _weather;
  List<String> _tags = [];
  List<String> _imagePaths = [];
  bool _markdownPreview = false;
  bool _showLocationField = false;

  _DiaryEditorOrigin? _origin;
  bool _saving = false;
  bool _rebuildScheduled = false;

  @override
  void initState() {
    super.initState();
    I18n.localeListenable.addListener(_localeChanged);
    final e = widget.entry;
    _content = TextEditingController(text: e?.content ?? '');
    _tag = TextEditingController();
    _location = TextEditingController(text: e?.location ?? '');
    _showLocationField = (e?.location ?? '').trim().isNotEmpty;
    _date = e?.date ?? widget.initialDate ?? DateTime.now();
    _mood = e?.mood;
    _weather = e?.weather;
    _tags = [...?e?.tags];
    _imagePaths = [...?e?.imagePaths];
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_origin != null) {
      _authorityChanged();
      return;
    }
    final origin = _DiaryEditorOrigin(context);
    _origin = origin;
    origin.diary.addListener(_authorityChanged);
    origin.auth?.addListener(_authorityChanged);
    AccountLocalDataCleaner.accountDataGenerationListenable.addListener(
      _authorityChanged,
    );
  }

  void _authorityChanged() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_rebuildScheduled) return;
      _rebuildScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _rebuildScheduled = false;
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  void _localeChanged() {
    _authorityChanged();
  }

  @override
  void dispose() {
    I18n.localeListenable.removeListener(_localeChanged);
    _origin?.diary.removeListener(_authorityChanged);
    _origin?.auth?.removeListener(_authorityChanged);
    AccountLocalDataCleaner.accountDataGenerationListenable.removeListener(
      _authorityChanged,
    );
    _content.dispose();
    _tag.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final att = await NoteAttachmentPicker.pickFile();
    if (!mounted || att == null || att.uri.trim().isEmpty) return;
    if (!_imagePaths.contains(att.uri.trim())) {
      setState(() => _imagePaths.add(att.uri.trim()));
    }
  }

  Future<void> _save() async {
    final origin = _origin;
    if (origin == null || !origin.isCurrent(checkRoute: true) || _saving) {
      return;
    }
    setState(() => _saving = true);

    try {
      final text = _content.text.trim();
      final loc = _location.text.trim();
      if (text.isEmpty &&
          _mood == null &&
          _weather == null &&
          _tags.isEmpty &&
          loc.isEmpty &&
          _imagePaths.isEmpty) {
        if (widget.entry != null) {
          if (!origin.isCurrent(checkRoute: true)) return;
          await origin.diary.delete(widget.entry!.id);
        }
        if (!mounted || !origin.isCurrent(checkRoute: true)) return;
        Navigator.pop(context);
        return;
      }

      final entry = DiaryEntry(
        id: widget.entry?.id,
        date: _date,
        content: text,
        mood: _mood,
        weather: _weather,
        tags: _tags,
        imagePaths: List<String>.from(_imagePaths),
        location: loc.isEmpty ? null : loc,
        createdAt: widget.entry?.createdAt,
      );
      if (!origin.isCurrent(checkRoute: true)) return;
      await origin.diary.addOrUpdate(entry);
      if (!mounted || !origin.isCurrent(checkRoute: true)) return;
      Navigator.pop(context);
    } catch (_) {
      // Save or deletion failed or was rejected.
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<DiaryProvider>();
    final isCurrent = _origin != null && _origin!.isCurrent(checkRoute: false);
    final enabled = isCurrent && !_saving;

    final lunar = LunarCalendar.fromSolar(_date);
    final cs = Theme.of(context).colorScheme;
    final routeBackground = Theme.of(context).brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;
    final surfaceStyle = appSurfaceStyleOf(context);
    final isLiquidGlass = surfaceStyle == AppSurfaceStyle.liquidGlass;
    final scaffold = Scaffold(
      backgroundColor: isLiquidGlass ? Colors.transparent : routeBackground,
      appBar: AppBar(
        title: Text(I18n.tr('diary.title')),
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
        backgroundColor: routeBackground.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: enabled ? _save : null,
          ),
        ],
      ),
      body: AppSecondaryControlTheme(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!isCurrent) ...[
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      RecommendedGoalsUiCopy.expired,
                      style: TextStyle(
                        fontSize: 15,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () {
                        if (!mounted) return;
                        final route = ModalRoute.of(context);
                        if (route != null &&
                            (!route.isActive || !route.isCurrent)) {
                          return;
                        }
                        Navigator.of(context).maybePop();
                      },
                      child: Text(I18n.tr('action.back')),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Date and lunar context.
              GestureDetector(
                onTap: !enabled
                    ? null
                    : () async {
                        final picked = await AppDatePicker.pickSolar(
                          context,
                          initialDate: _date,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2099, 12, 31),
                          titleKey: 'diary.editor.date_title',
                        );
                        if (!mounted ||
                            _origin == null ||
                            !_origin!.isCurrent(checkRoute: true)) {
                          return;
                        }
                        if (picked != null) setState(() => _date = picked);
                      },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(
                      appSurfaceStyleOf(context)?.smallTileRadius ??
                          DesignTokens.radiusControl,
                    ),
                  ),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Icon(Icons.calendar_today, size: 16, color: cs.primary),
                      Text(
                        AppDateFormat.date(context, _date),
                        style: TextStyle(
                          color: cs.primary,
                          fontWeight: FontWeight.normal,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(
                        AlmanacLocaleFormat.formatLunarDate(lunar),
                        style: TextStyle(
                          color: cs.primary.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Mood selector.
              Text(
                I18n.tr('diary.editor.mood_prompt'),
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: Mood.values.map((m) {
                  final selected = _mood == m;
                  return GestureDetector(
                    onTap: !enabled
                        ? null
                        : () => setState(() => _mood = selected ? null : m),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: selected
                            ? cs.primary.withValues(alpha: 0.15)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(
                          appSurfaceStyleOf(context)?.smallTileRadius ??
                              DesignTokens.radiusControl,
                        ),
                        border: Border.all(
                          color: selected ? cs.primary : cs.outlineVariant,
                          width: 0.45,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(m.emoji, style: const TextStyle(fontSize: 24)),
                          const SizedBox(height: 2),
                          Text(
                            _moodLabel(m),
                            style: const TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              // Weather selector.
              Text(
                I18n.tr('diary.editor.weather'),
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: Weather.values.map((w) {
                  final selected = _weather == w;
                  return FilterChip(
                    label: Text('${w.emoji} ${_weatherLabel(w)}'),
                    selected: selected,
                    onSelected: !enabled
                        ? null
                        : (_) => setState(() => _weather = selected ? null : w),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              // Tags.
              LayoutBuilder(
                builder: (context, constraints) {
                  final textScaler = MediaQuery.textScalerOf(context);
                  final hintText = I18n.tr('diary.editor.tag_hint');
                  final theme = Theme.of(context);
                  final hintStyle = (theme.textTheme.titleMedium ??
                          theme.inputDecorationTheme.hintStyle ??
                          const TextStyle(fontSize: 16))
                      .copyWith(
                        fontWeight: FontWeight.normal,
                        color: cs.onSurfaceVariant,
                      );
                  final painter = TextPainter(
                    text: TextSpan(text: hintText, style: hintStyle),
                    textScaler: textScaler,
                    textDirection: Directionality.of(context),
                  )..layout();
                  final exceeds = painter.width > (constraints.maxWidth - 64.0);
                  painter.dispose();
                  final isCompactOrScaled =
                      constraints.maxWidth < 360 ||
                      textScaler.scale(1.0) > 1.25 ||
                      exceeds;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isCompactOrScaled) ...[
                        ExcludeSemantics(
                          child: Text(
                            hintText,
                            key: const ValueKey('diary_editor_tag_hint'),
                            softWrap: true,
                            style: hintStyle,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: Semantics(
                              label: isCompactOrScaled ? hintText : null,
                              child: TextField(
                                controller: _tag,
                                enabled: enabled,
                                decoration: InputDecoration(
                                  hintText: isCompactOrScaled ? null : hintText,
                                  prefixIcon: const Icon(Icons.tag),
                                ),
                                onSubmitted: (v) {
                                  if (!enabled) return;
                                  if (v.trim().isNotEmpty) {
                                    setState(() {
                                      _tags.add(v.trim());
                                      _tag.clear();
                                    });
                                  }
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
              if (_tags.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: _tags
                      .map(
                        (t) => Chip(
                          label: Text(t),
                          onDeleted: !enabled
                              ? null
                              : () => setState(() => _tags.remove(t)),
                        ),
                      )
                      .toList(),
                ),
              ],
              if (_showLocationField) ...[
                const SizedBox(height: 14),
                TextField(
                  key: const ValueKey('diary_editor_location_field'),
                  controller: _location,
                  enabled: enabled,
                  decoration: InputDecoration(
                    hintText: I18n.current == AppLocale.en
                        ? 'Add location (optional)'
                        : '添加地点（可选）',
                    prefixIcon: const Icon(Icons.location_on_outlined),
                    suffixIcon: !enabled
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => setState(() {
                              _location.clear();
                              _showLocationField = false;
                            }),
                          ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
              const SizedBox(height: 14),
              // Location chip (when collapsed), Photos / Attachments & Mode Toggle.
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (!_showLocationField)
                        ActionChip(
                          key: const ValueKey('diary_editor_add_location_btn'),
                          avatar: const Icon(
                            Icons.location_on_outlined,
                            size: 16,
                          ),
                          label: Text(
                            I18n.current == AppLocale.en
                                ? 'Add location'
                                : '添加位置',
                          ),
                          onPressed: enabled
                              ? () => setState(() => _showLocationField = true)
                              : null,
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      OutlinedButton.icon(
                        key: const ValueKey('diary_editor_add_image_btn'),
                        onPressed: enabled ? _pickImage : null,
                        icon: const Icon(
                          Icons.photo_library_outlined,
                          size: 18,
                        ),
                        label: Text(
                          I18n.current == AppLocale.en ? 'Add Photo' : '添加图片',
                        ),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ChoiceChip(
                        key: const ValueKey('diary_editor_edit_mode'),
                        label: Text(
                          I18n.current == AppLocale.en ? 'Edit' : '编辑',
                          style: const TextStyle(fontSize: 12),
                        ),
                        selected: !_markdownPreview,
                        onSelected: (_) =>
                            setState(() => _markdownPreview = false),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      ChoiceChip(
                        key: const ValueKey('diary_editor_preview_mode'),
                        label: Text(
                          I18n.current == AppLocale.en
                              ? 'Preview'
                              : 'Markdown 预览',
                          style: const TextStyle(fontSize: 12),
                        ),
                        selected: _markdownPreview,
                        onSelected: (_) =>
                            setState(() => _markdownPreview = true),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ],
                  ),
                ],
              ),
              if (_imagePaths.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < _imagePaths.length; i++)
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          _DiaryImageThumb(path: _imagePaths[i], size: 72),
                          if (enabled)
                            Positioned(
                              top: -6,
                              right: -6,
                              child: GestureDetector(
                                onTap: () =>
                                    setState(() => _imagePaths.removeAt(i)),
                                child: Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    color: cs.errorContainer,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: cs.surface,
                                      width: 0.45,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.close,
                                    size: 13,
                                    color: cs.onErrorContainer,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              // Body.
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(
                    appSurfaceStyleOf(context)?.smallTileRadius ??
                        DesignTokens.radiusControl,
                  ),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.14),
                    width: 0.45,
                  ),
                ),
                child: _markdownPreview
                    ? ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 168),
                        child: _content.text.trim().isEmpty
                            ? Text(
                                I18n.tr('diary.editor.content_hint'),
                                style: TextStyle(
                                  fontSize: 15,
                                  color: cs.onSurfaceVariant,
                                ),
                              )
                            : _DiaryMarkdownBody(content: _content.text),
                      )
                    : TextField(
                        controller: _content,
                        enabled: enabled,
                        maxLines: 12,
                        minLines: 8,
                        decoration: InputDecoration(
                          hintText: I18n.tr('diary.editor.content_hint'),
                          border: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          enabledBorder: InputBorder.none,
                        ),
                        style: const TextStyle(fontSize: 15, height: 1.6),
                      ),
              ),
            ],
          ],
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

class _DiaryImageThumb extends StatelessWidget {
  final String path;
  final double size;

  const _DiaryImageThumb({required this.path, required this.size});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final trimmed = path.trim();
    final cachePx = ImageDecodeCache.boundedCachePixels(
      size,
      MediaQuery.devicePixelRatioOf(context),
    );
    Widget child;

    if (trimmed.startsWith('data:image/')) {
      final bytes = ImageDecodeCache.decodeBase64Image(trimmed);
      if (bytes != null) {
        child = Image.memory(
          bytes,
          fit: BoxFit.cover,
          cacheWidth: cachePx,
          cacheHeight: cachePx,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => _fallback(cs, trimmed),
        );
      } else {
        child = _fallback(cs, trimmed);
      }
    } else if (trimmed.startsWith('http://') ||
        trimmed.startsWith('https://')) {
      child = Image.network(
        trimmed,
        fit: BoxFit.cover,
        cacheWidth: cachePx,
        cacheHeight: cachePx,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _fallback(cs, trimmed),
      );
    } else if (!kIsWeb && trimmed.isNotEmpty) {
      child = Image.file(
        File(trimmed),
        fit: BoxFit.cover,
        cacheWidth: cachePx,
        cacheHeight: cachePx,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _fallback(cs, trimmed),
      );
    } else {
      child = _fallback(cs, trimmed);
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(
          appSurfaceStyleOf(context)?.smallTileRadius ??
              DesignTokens.radiusControl,
        ),
        border: Border.all(color: cs.outlineVariant, width: 0.45),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Widget _fallback(ColorScheme cs, String raw) {
    final label = raw.split(RegExp(r'[/\\]')).last;
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.image_outlined, size: 18, color: cs.onSurfaceVariant),
          if (label.isNotEmpty)
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

class _DiaryMarkdownBody extends StatelessWidget {
  final String content;
  final bool compact;

  const _DiaryMarkdownBody({required this.content, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final allBlocks = NoteBlock.fromMarkdown(content);
    final blocks = compact ? allBlocks.take(6).toList() : allBlocks;
    return Column(
      key: const ValueKey('diary_markdown_preview_body'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final block in blocks) _buildBlock(context, block, cs),
      ],
    );
  }

  Widget _buildBlock(BuildContext context, NoteBlock block, ColorScheme cs) {
    return switch (block.type) {
      NoteBlockType.divider => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Divider(
          height: 1,
          thickness: 0.45,
          color: cs.outlineVariant,
        ),
      ),
      NoteBlockType.heading => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          block.text,
          style: TextStyle(
            fontSize: block.level <= 1 ? 17 : 15.5,
            color: cs.primary,
            fontWeight: FontWeight.normal,
            height: 1.4,
          ),
        ),
      ),
      NoteBlockType.quote => Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.fromLTRB(10, 4, 8, 4),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: cs.primary, width: 0.6)),
          color: cs.primary.withValues(alpha: 0.06),
        ),
        child: Text(
          block.text,
          style: TextStyle(
            fontSize: 13.5,
            color: cs.onSurface.withValues(alpha: 0.8),
            fontStyle: FontStyle.italic,
            height: 1.45,
          ),
        ),
      ),
      NoteBlockType.bullet => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('• ', style: TextStyle(fontSize: 14, color: cs.primary)),
            Expanded(
              child: Text(
                block.text,
                style: TextStyle(
                  fontSize: 14,
                  color: cs.onSurface.withValues(alpha: 0.82),
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      ),
      NoteBlockType.checklist => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              block.checked ? Icons.check_box : Icons.check_box_outline_blank,
              size: 15,
              color: block.checked ? cs.primary : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                block.text,
                style: TextStyle(
                  fontSize: 14,
                  decoration: block.checked ? TextDecoration.lineThrough : null,
                  color: cs.onSurface.withValues(alpha: 0.82),
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      ),
      NoteBlockType.code => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
        ),
        child: Text(
          block.text,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12.5,
            color: cs.onSurface,
          ),
        ),
      ),
      NoteBlockType.paragraph => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          block.text,
          style: TextStyle(
            fontSize: 14,
            color: cs.onSurface.withValues(alpha: 0.84),
            height: 1.5,
          ),
        ),
      ),
    };
  }
}
