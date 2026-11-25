import 'dart:async';
import 'package:duoyi/desktop_web/desktop_embedded_scope.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/desktop_tokens.dart';
import '../core/global_search.dart';
import '../core/i18n.dart';
import '../providers/anniversary_provider.dart';
import '../providers/calendar_provider.dart';
import '../providers/countdown_provider.dart';
import '../providers/course_provider.dart';
import '../providers/diary_provider.dart';
import '../providers/goal_provider.dart';
import '../providers/habit_provider.dart';
import '../providers/note_provider.dart';
import '../providers/pomodoro_provider.dart';
import '../providers/time_audit_provider.dart';
import '../providers/todo_provider.dart';
import '../services/account_local_data_cleaner.dart';
import '../widgets/brand_background.dart';
import '../widgets/empty_state.dart';
import '../widgets/surface_components.dart';
import 'anniversary_screen.dart';
import 'calendar_screen.dart';
import 'countdown_screen.dart';
import 'course_schedule_screen.dart';
import 'diary_screen.dart';
import 'goal_screen.dart';
import 'habit_detail_screen.dart';
import 'habit_screen.dart';
import 'note_screen.dart';
import 'pomodoro_screen.dart';
import 'time_audit_screen.dart';
import 'todo_detail_screen.dart';

class SearchScreen extends StatefulWidget
    implements LocaleStatePreservingRoute {
  static const String recentHistoryPrefsKey = 'search_recent_queries_v1';
  static const int maxRecentQueries = 8;

  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  List<SearchHit> _hits = [];
  String _query = '';
  SearchKind? _selectedKind;
  List<String> _recentQueries = const [];

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_syncControllerState);
    I18n.localeListenable.addListener(_onLocaleChanged);
    unawaited(_loadRecentQueries());
  }

  @override
  void dispose() {
    I18n.localeListenable.removeListener(_onLocaleChanged);
    _ctrl.removeListener(_syncControllerState);
    _ctrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  void _syncControllerState() {
    if (mounted) setState(() {});
  }

  Future<void> _loadRecentQueries() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved =
          prefs.getStringList(SearchScreen.recentHistoryPrefsKey) ??
          const <String>[];
      final cleaned = _sanitizeHistory(saved);
      if (!mounted) return;
      if (!_listEquals(cleaned, _recentQueries)) {
        setState(() => _recentQueries = cleaned);
      }
    } catch (_) {
      // Ignore storage errors on constrained/mock test bindings.
    }
  }

  Future<void> _recordRecentQuery(String raw) async {
    final q = raw.trim();
    if (q.isEmpty) return;
    final next = <String>[
      q,
      ..._recentQueries.where((item) => item != q),
    ].take(SearchScreen.maxRecentQueries).toList(growable: false);
    if (_listEquals(next, _recentQueries)) return;
    if (mounted) {
      setState(() => _recentQueries = next);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(SearchScreen.recentHistoryPrefsKey, next);
    } catch (_) {
      // Ignore storage errors cleanly.
    }
  }

  Future<void> _clearRecentQueries() async {
    if (_recentQueries.isEmpty) return;
    if (mounted) {
      setState(() => _recentQueries = const []);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(SearchScreen.recentHistoryPrefsKey);
    } catch (_) {
      // Ignore storage errors cleanly.
    }
  }

  static List<String> _sanitizeHistory(List<String> raw) {
    final seen = <String>{};
    final out = <String>[];
    for (final item in raw) {
      final trimmed = item.trim();
      if (trimmed.isNotEmpty && seen.add(trimmed)) {
        out.add(trimmed);
        if (out.length >= SearchScreen.maxRecentQueries) break;
      }
    }
    return List<String>.unmodifiable(out);
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _applySearch(String raw, {bool recordHistory = true}) {
    final q = raw.trim();
    if (!mounted) return;
    if (q.isEmpty) {
      setState(() {
        _hits = [];
        _query = '';
        _selectedKind = null;
      });
      return;
    }
    final hits = GlobalSearch.run(
      query: q,
      todos: context.read<TodoProvider>().todos,
      habits: context.read<HabitProvider>().habits,
      notes: context.read<NoteProvider>().notes,
      diaries: context.read<DiaryProvider>().entries,
      anniversaries: context.read<AnniversaryProvider>().items,
      countdowns: context.read<CountdownProvider>().items,
      goals: context.read<GoalProvider>().goals,
      courses: context.read<CourseProvider>().courses,
      calendarEvents: context.read<CalendarProvider>().events,
      timeEntries: context.read<TimeAuditProvider>().entries,
      pomodoroSessions:
          context.read<PomodoroProvider?>()?.sessions ?? const [],
    );
    setState(() {
      _hits = hits;
      _query = q;
      if (_selectedKind != null && !hits.any((h) => h.kind == _selectedKind)) {
        _selectedKind = null;
      }
    });
    if (recordHistory && hits.isNotEmpty) {
      unawaited(_recordRecentQuery(q));
    }
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), () {
      _applySearch(v);
    });
  }

  void _onSubmitted(String v) {
    _debounce?.cancel();
    final q = v.trim();
    if (q.isNotEmpty) {
      unawaited(_recordRecentQuery(q));
    }
    _applySearch(v, recordHistory: false);
  }

  void _selectRecentQuery(String query) {
    _debounce?.cancel();
    _ctrl.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    _applySearch(query);
  }

  void _open(SearchHit h) {
    unawaited(_recordRecentQuery(_query));
    switch (h.kind) {
      case SearchKind.todo:
        final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => BrandRouteSurface(
              child: TodoDetailScreen(
                todoId: h.sourceId,
                accountGeneration: accountGeneration,
              ),
            ),
          ),
        );
        break;
      case SearchKind.habit:
        final hasHabit = context.read<HabitProvider>().habits.any(
          (item) => item.id == h.sourceId,
        );
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => BrandRouteSurface(
              child: hasHabit && h.sourceId.isNotEmpty
                  ? HabitDetailScreen(habitId: h.sourceId)
                  : const HabitScreen(),
            ),
          ),
        );
        break;
      case SearchKind.note:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                BrandRouteSurface(child: NoteScreen(initialNoteId: h.sourceId)),
          ),
        );
        break;
      case SearchKind.diary:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => BrandRouteSurface(
              child: DiaryScreen(initialEntryId: h.sourceId),
            ),
          ),
        );
        break;
      case SearchKind.anniversary:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => BrandRouteSurface(
              child: AnniversaryScreen(initialAnniversaryId: h.sourceId),
            ),
          ),
        );
        break;
      case SearchKind.countdown:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => BrandRouteSurface(
              child: CountdownScreen(initialCountdownId: h.sourceId),
            ),
          ),
        );
        break;
      case SearchKind.goal:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                BrandRouteSurface(child: GoalScreen(initialGoalId: h.sourceId)),
          ),
        );
        break;
      case SearchKind.course:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => BrandRouteSurface(
              child: CourseScheduleScreen(initialCourseId: h.sourceId),
            ),
          ),
        );
        break;
      case SearchKind.calendarEvent:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                BrandRouteSurface(child: CalendarScreen(initialDate: h.when)),
          ),
        );
        break;
      case SearchKind.timeEntry:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => BrandRouteSurface(
              child: TimeAuditScreen(
                initialEntryId: h.sourceId,
                openInitialEntrySheet: false,
              ),
            ),
          ),
        );
        break;
      case SearchKind.pomodoro:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const BrandRouteSurface(child: PomodoroScreen()),
          ),
        );
        break;
    }
  }

  Color _accessibleHighlightColor(
    Color background,
    Color preferred,
    bool isDark,
  ) {
    if (appContrastRatio(background, preferred) >= 5.0) return preferred;
    final target = isDark ? Colors.white : Colors.black;
    for (final amount in const [0.18, 0.24, 0.30, 0.38]) {
      final candidate = Color.lerp(preferred, target, amount) ?? preferred;
      if (appContrastRatio(background, candidate) >= 5.0) {
        return candidate;
      }
    }
    return appReadableForeground(background, preferred);
  }

  Widget _highlight(String text, String q, Color highlightColor) {
    if (q.isEmpty) return Text(text);
    final lower = text.toLowerCase();
    final qLower = q.toLowerCase();
    final idx = lower.indexOf(qLower);
    if (idx < 0) return Text(text);
    final end = idx + q.length;
    return RichText(
      textScaler: MediaQuery.textScalerOf(context),
      text: TextSpan(
        style: DefaultTextStyle.of(context).style,
        children: [
          TextSpan(text: text.substring(0, idx)),
          TextSpan(
            text: text.substring(idx, end),
            style: TextStyle(
              color: highlightColor,
              fontWeight: FontWeight.normal,
            ),
          ),
          TextSpan(text: text.substring(end)),
        ],
      ),
    );
  }

  Widget _resultCard(SearchHit h) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final surfaceStyle = appSurfaceStyleOf(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = surfaceStyle?.cardFillColor != null
        ? Color.alphaBlend(surfaceStyle!.cardFillColor!, cs.surface)
        : cs.surface;
    final highlightColor = _accessibleHighlightColor(
      cardBg,
      cs.primary,
      isDark,
    );
    final pillBg = Color.alphaBlend(
      cs.primary.withValues(alpha: 0.1),
      cardBg,
    );
    final pillFg = appReadableForeground(pillBg, cs.primary);
    final secondaryFg = appSecondaryDescriptionColor(context);

    return AppSurfaceCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      onTap: () => _open(h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(h.icon, size: 20, color: cs.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          h.kindLabel,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: pillFg,
                            fontWeight: FontWeight.normal,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      if (h.when != null)
                        Text(
                          '${h.when!.month}/${h.when!.day}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: secondaryFg,
                            fontWeight: FontWeight.normal,
                            fontSize: 11,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                DefaultTextStyle(
                  style: theme.textTheme.bodyMedium!.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.normal,
                    color: cs.onSurface,
                    height: 1.25,
                  ),
                  child: _highlight(h.title, _query, highlightColor),
                ),
                if (h.subtitle != null && h.subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  DefaultTextStyle(
                    style: theme.textTheme.bodySmall!.copyWith(
                      color: secondaryFg,
                      height: 1.35,
                    ),
                    child: _highlight(h.subtitle!, _query, highlightColor),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _kindLabelFor(SearchKind kind) => switch (kind) {
    SearchKind.todo => I18n.tr('search.kind.todo'),
    SearchKind.habit => I18n.tr('search.kind.habit'),
    SearchKind.note => I18n.tr('search.kind.note'),
    SearchKind.diary => I18n.tr('search.kind.diary'),
    SearchKind.anniversary => I18n.tr('search.kind.anniversary'),
    SearchKind.countdown => I18n.tr('search.kind.countdown'),
    SearchKind.goal => I18n.tr('search.kind.goal'),
    SearchKind.course => I18n.tr('search.kind.course'),
    SearchKind.calendarEvent => I18n.tr('search.kind.event'),
    SearchKind.timeEntry => I18n.tr('search.kind.time_entry'),
    SearchKind.pomodoro => I18n.current == AppLocale.en ? 'Focus' : '专注记录',
  };

  Widget _buildEmptyOrHistory(
    BuildContext context,
    ThemeData theme,
    ColorScheme cs,
  ) {
    if (_recentQueries.isEmpty) {
      return EmptyState(icon: Icons.search, message: I18n.tr('search.empty'));
    }
    final isEn = I18n.current == AppLocale.en;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: DesktopTokens.secondaryMaxContentWidth,
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
          children: [
            EmptyState(icon: Icons.search, message: I18n.tr('search.empty')),
            const SizedBox(height: 16),
            AppSurfaceCard(
              key: const ValueKey('search_recent_history_card'),
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.history, size: 16, color: cs.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          isEn ? 'Recent searches' : '最近搜索',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.normal,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                      TextButton(
                        key: const ValueKey('search_clear_history'),
                        onPressed: _clearRecentQueries,
                        child: Text(isEn ? 'Clear' : '清空'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final q in _recentQueries)
                        ActionChip(
                          avatar: const Icon(Icons.history, size: 14),
                          label: Text(q),
                          onPressed: () => _selectRecentQuery(q),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKindFilterStrip(BuildContext context) {
    final counts = <SearchKind, int>{};
    for (final hit in _hits) {
      counts[hit.kind] = (counts[hit.kind] ?? 0) + 1;
    }
    final activeKinds = [
      for (final kind in SearchKind.values)
        if ((counts[kind] ?? 0) > 0) kind,
    ];
    if (activeKinds.length <= 1) {
      return const SizedBox.shrink();
    }
    final isEn = I18n.current == AppLocale.en;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: SizedBox(
        height: 38,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            FilterChip(
              key: const ValueKey('search_filter_all'),
              selected: _selectedKind == null,
              label: Text(
                isEn ? 'All (${_hits.length})' : '全部 (${_hits.length})',
                style: const TextStyle(
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              onSelected: (_) {
                if (mounted) setState(() => _selectedKind = null);
              },
            ),
            for (final kind in activeKinds) ...[
              const SizedBox(width: 8),
              FilterChip(
                key: ValueKey('search_filter_${kind.name}'),
                selected: _selectedKind == kind,
                label: Text(
                  '${_kindLabelFor(kind)} (${counts[kind]})',
                  style: const TextStyle(
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                onSelected: (_) {
                  if (mounted) {
                    setState(() {
                      _selectedKind = _selectedKind == kind ? null : kind;
                    });
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final routeBackground = theme.brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;
    final hasBrandBackground =
        DesktopEmbeddedHostScope.isHosted(context) ||
        context.findAncestorWidgetOfExactType<BrandBackground>() != null;
    final visibleHits = _selectedKind == null
        ? _hits
        : _hits
              .where((h) => h.kind == _selectedKind)
              .toList(growable: false);
    return BrandScaffold(
      paintBackground: !hasBrandBackground,
      appBar: AppBar(
        backgroundColor: routeBackground.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            border: InputBorder.none,
            hintText: I18n.tr('search.hint'),
          ),
          onChanged: _onChanged,
          onSubmitted: _onSubmitted,
        ),
        actions: [
          if (_ctrl.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: I18n.tr('search.clear'),
              onPressed: () {
                _ctrl.clear();
                _onChanged('');
              },
            ),
        ],
      ),
      body: AppSecondaryControlTheme(
        child: _query.isEmpty
            ? _buildEmptyOrHistory(context, theme, cs)
            : _hits.isEmpty
            ? EmptyState(
                icon: Icons.sentiment_dissatisfied,
                message:
                    '${I18n.tr('search.no_results.prefix')}"$_query"${I18n.tr('search.no_results.suffix')}',
              )
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: DesktopTokens.secondaryMaxContentWidth,
                  ),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                    children: [
                  AppSurfaceCard(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(Icons.search, color: cs.primary),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                I18n.tr('search.results.title'),
                                style: appSecondaryMenuItemTextStyle(context)
                                    .copyWith(
                                      fontSize: 13,
                                      fontWeight: FontWeight.normal,
                                      color: cs.onSurface,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${I18n.tr('search.results.summary_prefix')}$_query${I18n.tr('search.results.summary_middle')}${_hits.length}${I18n.tr('search.results.summary_suffix')}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: appSecondaryDescriptionColor(context),
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: I18n.tr('search.clear'),
                          onPressed: () {
                            _ctrl.clear();
                            _onChanged('');
                          },
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  _buildKindFilterStrip(context),
                  const SizedBox(height: 12),
                  ...visibleHits.map(_resultCard),
                ],
              ),
                ),
              ),
      ),
    );
  }
}
