import 'package:flutter/material.dart';

import '../core/almanac_locale_format.dart';
import '../core/almanac_ui_copy.dart';
import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../core/i18n_date_format.dart';
import '../core/lunar_calendar.dart';
import '../services/almanac_tools_service.dart';
import '../services/holiday_calendar.dart';
import '../widgets/app_date_format.dart';
import '../widgets/app_date_picker.dart';
import '../widgets/brand_background.dart'
    show BrandRouteSurface, LocaleStatePreservingRoute;
import '../widgets/surface_components.dart';
import 'almanac_screen.dart';

/// 万年历工具中心（P0/P1/P2）：
/// 0: 择吉日查询
/// 1: 法定放假安排与倒计时
/// 2: 日期计算与公农历互转
/// 3: 全年 24 节气表与生辰八字简排
class AlmanacToolsScreen extends StatefulWidget
    implements LocaleStatePreservingRoute {
  final int initialTab;
  final DateTime? initialDate;
  final String? initialActivity;
  final DateTime? initialSecondDate;

  const AlmanacToolsScreen({
    super.key,
    this.initialTab = 0,
    this.initialDate,
    this.initialActivity,
    this.initialSecondDate,
  });

  @override
  State<AlmanacToolsScreen> createState() => _AlmanacToolsScreenState();
}

class _AlmanacToolsScreenState extends State<AlmanacToolsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      initialIndex: widget.initialTab.clamp(0, 3),
      vsync: this,
    );
    I18n.localeListenable.addListener(_onLocaleChanged);
  }

  void _onLocaleChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    I18n.localeListenable.removeListener(_onLocaleChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _openAlmanacDate(DateTime date) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BrandRouteSurface(child: AlmanacScreen(initialDate: date)),
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
    final baseDate = _dateOnly(widget.initialDate ?? DateTime.now());

    return Scaffold(
      backgroundColor: routeBackground,
      appBar: AppBar(
        title: Text(AlmanacUiCopy.almanacToolsTitle),
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
        centerTitle: false,
        titleSpacing: 4,
        leadingWidth: 44,
        backgroundColor: routeBackground.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: cs.primary,
          unselectedLabelColor: cs.onSurfaceVariant,
          indicatorColor: cs.primary,
          dividerColor: cs.outlineVariant.withValues(alpha: 0.20),
          labelStyle: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.normal,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.normal,
          ),
          tabs: [
            Tab(
              key: const ValueKey('almanac_tools_tab_0'),
              text: AlmanacUiCopy.tabAuspiciousPicker,
            ),
            Tab(
              key: const ValueKey('almanac_tools_tab_1'),
              text: AlmanacUiCopy.tabHolidaySchedule,
            ),
            Tab(
              key: const ValueKey('almanac_tools_tab_2'),
              text: AlmanacUiCopy.tabDateTools,
            ),
            Tab(
              key: const ValueKey('almanac_tools_tab_3'),
              text: AlmanacUiCopy.tabSolarTermsBazi,
            ),
          ],
        ),
      ),
      body: ColoredBox(
        color: routeBackground.withValues(alpha: 0.92),
        child: TabBarView(
          controller: _tabController,
          children: [
            _AuspiciousFinderTab(
              initialDate: baseDate,
              initialActivity: widget.initialActivity,
              onOpenAlmanac: _openAlmanacDate,
            ),
            _HolidayScheduleTab(
              initialDate: baseDate,
              onOpenAlmanac: _openAlmanacDate,
            ),
            _DateToolsTab(
              initialDate: baseDate,
              initialSecondDate: widget.initialSecondDate,
              onOpenAlmanac: _openAlmanacDate,
            ),
            _SolarTermsBaziTab(
              initialDate: baseDate,
              onOpenAlmanac: _openAlmanacDate,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 1: 择吉日查询
// ---------------------------------------------------------------------------
class _AuspiciousFinderTab extends StatefulWidget {
  final DateTime initialDate;
  final String? initialActivity;
  final ValueChanged<DateTime> onOpenAlmanac;

  const _AuspiciousFinderTab({
    required this.initialDate,
    required this.initialActivity,
    required this.onOpenAlmanac,
  });

  @override
  State<_AuspiciousFinderTab> createState() => _AuspiciousFinderTabState();
}

class _AuspiciousFinderTabState extends State<_AuspiciousFinderTab> {
  static const List<int> _rangeOptions = <int>[30, 90, 180, 365];

  late final TextEditingController _queryController;
  late DateTime _startDate;
  int _rangeDays = 90;
  bool _weekendsOrHolidaysOnly = false;
  String? _avoidZodiac;

  @override
  void initState() {
    super.initState();
    _startDate = _clampSupportedSolar(widget.initialDate);
    final seed = widget.initialActivity?.trim();
    _queryController = TextEditingController(
      text: (seed != null && seed.isNotEmpty) ? seed : '嫁娶',
    );
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _pickStartDate() async {
    final picked = await AppDatePicker.pickSolar(
      context,
      initialDate: _startDate,
      firstDate: DateTime(1900),
      lastDate: DateTime(2099, 12, 31),
      title: AlmanacUiCopy.startDateLabel,
    );
    if (!mounted || picked == null) return;
    setState(() => _startDate = _clampSupportedSolar(picked));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final surfaceStyle = appSurfaceStyleOf(context);
    final cardRadius = surfaceStyle?.cardRadius ?? DesignTokens.radiusCard;
    final query = _queryController.text.trim();
    final matches = query.isEmpty
        ? const <AuspiciousDayMatch>[]
        : AlmanacToolsService.findAuspiciousDays(
            activity: query,
            startDate: _startDate,
            rangeDays: _rangeDays,
            weekendsOrHolidaysOnly: _weekendsOrHolidaysOnly,
            avoidZodiac: _avoidZodiac,
          );

    return Scrollbar(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          14,
          12,
          14,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppSurfaceCard(
                  padding: const EdgeInsets.all(14),
                  borderRadius: BorderRadius.circular(cardRadius),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.18),
                    width: 0.45,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AlmanacUiCopy.selectActivityLabel,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: cs.onSurface,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        key: const ValueKey('auspicious_activity_input'),
                        controller: _queryController,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: AlmanacUiCopy.searchActivityHint,
                          prefixIcon: const Icon(Icons.search_rounded, size: 19),
                          suffixIcon: query.isEmpty
                              ? null
                              : IconButton(
                                  onPressed: () {
                                    _queryController.clear();
                                    setState(() {});
                                  },
                                  icon: const Icon(Icons.close_rounded, size: 18),
                                ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              DesignTokens.radiusControl,
                            ),
                            borderSide: BorderSide(
                              color: cs.outlineVariant.withValues(alpha: 0.35),
                              width: 0.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final preset
                              in AlmanacToolsService.presetActivities)
                            ChoiceChip(
                              key: ValueKey(
                                'auspicious_preset_${preset.key}',
                              ),
                              label: Text(
                                preset.localizedLabel(),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.normal,
                                ),
                              ),
                              selected:
                                  query == preset.key ||
                                  query == preset.labelZh ||
                                  query.toLowerCase() ==
                                      preset.labelEn.toLowerCase(),
                              selectedColor: cs.primary.withValues(alpha: 0.14),
                              side: BorderSide(
                                color: cs.outlineVariant.withValues(alpha: 0.32),
                                width: 0.45,
                              ),
                              onSelected: (_) {
                                _queryController.text = preset.key;
                                setState(() {});
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ActionChip(
                            key: const ValueKey('auspicious_start_date_chip'),
                            avatar: Icon(
                              Icons.calendar_today_outlined,
                              size: 15,
                              color: cs.primary,
                            ),
                            label: Text(
                              '${AlmanacUiCopy.startDateLabel}: ${AppDateFormat.date(context, _startDate)}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.normal,
                              ),
                            ),
                            side: BorderSide(
                              color: cs.outlineVariant.withValues(alpha: 0.32),
                              width: 0.45,
                            ),
                            onPressed: _pickStartDate,
                          ),
                          for (final days in _rangeOptions)
                            ChoiceChip(
                              key: ValueKey('auspicious_range_$days'),
                              label: Text(
                                AlmanacUiCopy.rangeDaysOption(days),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.normal,
                                ),
                              ),
                              selected: _rangeDays == days,
                              selectedColor: cs.primary.withValues(alpha: 0.14),
                              side: BorderSide(
                                color: cs.outlineVariant.withValues(alpha: 0.32),
                                width: 0.45,
                              ),
                              onSelected: (_) =>
                                  setState(() => _rangeDays = days),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          FilterChip(
                            key: const ValueKey('auspicious_weekends_filter'),
                            selected: _weekendsOrHolidaysOnly,
                            label: Text(
                              AlmanacUiCopy.weekendsOrHolidaysOnlyLabel,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.normal,
                              ),
                            ),
                            selectedColor: cs.primary.withValues(alpha: 0.14),
                            side: BorderSide(
                              color: cs.outlineVariant.withValues(alpha: 0.32),
                              width: 0.45,
                            ),
                            onSelected: (v) =>
                                setState(() => _weekendsOrHolidaysOnly = v),
                          ),
                          PopupMenuButton<String>(
                            key: const ValueKey('auspicious_zodiac_filter'),
                            onSelected: (value) {
                              setState(() {
                                _avoidZodiac = value.isEmpty ? null : value;
                              });
                            },
                            itemBuilder: (context) => [
                              PopupMenuItem<String>(
                                value: '',
                                child: Text(AlmanacUiCopy.noZodiacFilterLabel),
                              ),
                              for (final z in AlmanacToolsService.zodiacOptions)
                                PopupMenuItem<String>(
                                  value: z,
                                  child: Text(
                                    AlmanacLocaleFormat.formatZodiac(z),
                                  ),
                                ),
                            ],
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: _avoidZodiac != null
                                    ? cs.primary.withValues(alpha: 0.12)
                                    : cs.surface,
                                borderRadius: BorderRadius.circular(
                                  DesignTokens.radiusSm,
                                ),
                                border: Border.all(
                                  color: cs.outlineVariant.withValues(alpha: 0.35),
                                  width: 0.45,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.pets_outlined,
                                    size: 14,
                                    color: cs.primary,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    _avoidZodiac == null
                                        ? '${AlmanacUiCopy.avoidZodiacLabel}: ${AlmanacUiCopy.noZodiacFilterLabel}'
                                        : '${AlmanacUiCopy.avoidZodiacLabel}: ${AlmanacLocaleFormat.formatZodiac(_avoidZodiac!)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: cs.onSurface,
                                      fontWeight: FontWeight.normal,
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  const Icon(Icons.arrow_drop_down, size: 16),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    AlmanacUiCopy.auspiciousMatchesSummary(matches.length),
                    key: const ValueKey('auspicious_matches_summary'),
                    style: TextStyle(
                      fontSize: 12.5,
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (matches.isEmpty)
                  AppSurfaceCard(
                    padding: const EdgeInsets.all(24),
                    borderRadius: BorderRadius.circular(cardRadius),
                    border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.16),
                      width: 0.45,
                    ),
                    child: Text(
                      AlmanacUiCopy.noAuspiciousDaysFound,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  for (final match in matches)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: AppSurfaceCard(
                        padding: const EdgeInsets.all(13),
                        borderRadius: BorderRadius.circular(cardRadius),
                        border: Border.all(
                          color: cs.outlineVariant.withValues(alpha: 0.18),
                          width: 0.45,
                        ),
                        onTap: () => widget.onOpenAlmanac(match.date),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        AlmanacUiCopy.fullDateTitle(
                                          match.date,
                                          null,
                                          AppDateFormat.patternOf(context),
                                        ),
                                        style: TextStyle(
                                          fontSize: 14.5,
                                          color: cs.onSurface,
                                          fontWeight: FontWeight.normal,
                                          fontFeatures: const [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                      ),
                                      _ToolPill(
                                        text: AlmanacLocaleFormat.formatLunarDate(
                                          match.lunarDate,
                                        ),
                                        color: cs.primary,
                                      ),
                                      if (match.isHoliday)
                                        _ToolPill(
                                          text: match.holidayName != null &&
                                                  match.holidayName!.isNotEmpty
                                              ? '${AlmanacUiCopy.holidayTag} · ${match.holidayName}'
                                              : AlmanacUiCopy.holidayTag,
                                          color: AlmanacPalette.holidayTeal(
                                            isDark: isDark,
                                          ),
                                        )
                                      else if (match.isWeekend &&
                                          !match.isWorkMakeupDay)
                                        _ToolPill(
                                          text: AlmanacUiCopy.weekendTag,
                                          color: AlmanacPalette.termGreen(
                                            isDark: isDark,
                                          ),
                                        ),
                                      if (match.tianShen.isNotEmpty)
                                        _ToolPill(
                                          text:
                                              '${AlmanacLocaleFormat.formatTianShen(match.tianShen)} · ${AlmanacLocaleFormat.formatTianShenType(match.tianShenType)}',
                                          color: match.isHuangDao
                                              ? AlmanacPalette.huangDaoAmber(
                                                  isDark: isDark,
                                                )
                                              : cs.onSurfaceVariant,
                                        ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  size: 19,
                                  color: cs.onSurfaceVariant,
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${AlmanacLocaleFormat.formatGanzhiLine(match.detail)} · ${AlmanacLocaleFormat.formatClash(match.detail)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${AlmanacUiCopy.auspiciousLabel}: ${AlmanacLocaleFormat.formatActivitiesPreview(match.detail.suitable, maxTerms: 6)}',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: cs.onSurface.withValues(alpha: 0.85),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 2: 法定放假安排与倒计时
// ---------------------------------------------------------------------------
class _HolidayScheduleTab extends StatefulWidget {
  final DateTime initialDate;
  final ValueChanged<DateTime> onOpenAlmanac;

  const _HolidayScheduleTab({
    required this.initialDate,
    required this.onOpenAlmanac,
  });

  @override
  State<_HolidayScheduleTab> createState() => _HolidayScheduleTabState();
}

class _HolidayScheduleTabState extends State<_HolidayScheduleTab> {
  late int _selectedYear;

  @override
  void initState() {
    super.initState();
    final years = HolidayCalendar.supportedYears;
    final preferred = widget.initialDate.year;
    _selectedYear = years.contains(preferred)
        ? preferred
        : (years.isNotEmpty ? years.last : preferred);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final surfaceStyle = appSurfaceStyleOf(context);
    final cardRadius = surfaceStyle?.cardRadius ?? DesignTokens.radiusCard;
    final holidayColor = AlmanacPalette.holidayTeal(isDark: isDark);
    final makeupColor = AlmanacPalette.makeupIndigo(isDark: isDark);
    final years = HolidayCalendar.supportedYears;
    final now = _dateOnly(DateTime.now());
    final nextHoliday = HolidayCalendar.nextHoliday(now);
    final schedules = HolidayCalendar.schedulesForYear(_selectedYear);

    return Scrollbar(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          14,
          12,
          14,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (nextHoliday != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: AppSurfaceCard(
                      key: const ValueKey('holiday_next_countdown_hero'),
                      padding: const EdgeInsets.all(15),
                      borderRadius: BorderRadius.circular(cardRadius),
                      color: Color.alphaBlend(
                        cs.primary.withValues(alpha: 0.08),
                        cs.surface,
                      ),
                      border: Border.all(
                        color: cs.primary.withValues(alpha: 0.25),
                        width: 0.5,
                      ),
                      onTap: () => widget.onOpenAlmanac(nextHoliday.startDate),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.celebration_outlined,
                                size: 18,
                                color: cs.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  AlmanacUiCopy.nextHolidayHeroTitle(
                                    nextHoliday,
                                    now,
                                  ),
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: cs.onSurface,
                                    fontWeight: FontWeight.normal,
                                  ),
                                ),
                              ),
                              _ToolPill(
                                text: AlmanacUiCopy.holidayDaysBadge(
                                  nextHoliday.totalDays,
                                ),
                                color: holidayColor,
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${I18nDateFormat.date(nextHoliday.startDate)} – ${I18nDateFormat.date(nextHoliday.endDate)}',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: cs.onSurfaceVariant,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          if (nextHoliday.localizedBridgeLeaveTip().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                '${AlmanacUiCopy.bridgeLeaveTipLabel}: ${nextHoliday.localizedBridgeLeaveTip()}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.primary,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final y in years)
                      ChoiceChip(
                        key: ValueKey('holiday_year_chip_$y'),
                        label: Text(
                          AlmanacUiCopy.yearHeader(y),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                        selected: _selectedYear == y,
                        selectedColor: cs.primary.withValues(alpha: 0.14),
                        side: BorderSide(
                          color: cs.outlineVariant.withValues(alpha: 0.32),
                          width: 0.45,
                        ),
                        onSelected: (_) => setState(() => _selectedYear = y),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                for (final item in schedules)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AppSurfaceCard(
                      key: ValueKey('holiday_card_${item.id}'),
                      padding: const EdgeInsets.all(14),
                      borderRadius: BorderRadius.circular(cardRadius),
                      border: Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0.18),
                        width: 0.45,
                      ),
                      onTap: () => widget.onOpenAlmanac(item.startDate),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.localizedName(),
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: cs.onSurface,
                                    fontWeight: FontWeight.normal,
                                  ),
                                ),
                              ),
                              _ToolPill(
                                text: AlmanacUiCopy.holidayDaysBadge(
                                  item.totalDays,
                                ),
                                color: holidayColor,
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${I18nDateFormat.date(item.startDate)} – ${I18nDateFormat.date(item.endDate)}',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: cs.onSurfaceVariant,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                '${AlmanacUiCopy.makeupWorkdaysLabel}:',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              if (item.makeupDates.isEmpty)
                                _ToolPill(
                                  text: AlmanacUiCopy.noMakeupWorkdaysLabel,
                                  color: cs.onSurfaceVariant,
                                )
                              else
                                for (final m in item.makeupDates)
                                  ActionChip(
                                    visualDensity: VisualDensity.compact,
                                    label: Text(
                                      I18nDateFormat.monthDay(m),
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: appReadableForeground(
                                          cs.surface,
                                          makeupColor,
                                        ),
                                        fontWeight: FontWeight.normal,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                    side: BorderSide(
                                      color: makeupColor.withValues(
                                        alpha: 0.28,
                                      ),
                                      width: 0.45,
                                    ),
                                    onPressed: () => widget.onOpenAlmanac(m),
                                  ),
                            ],
                          ),
                          if (item.localizedBridgeLeaveTip().isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: cs.primary.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(
                                  DesignTokens.radiusSm,
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.lightbulb_outline_rounded,
                                    size: 15,
                                    color: cs.primary,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      '${AlmanacUiCopy.bridgeLeaveTipLabel}: ${item.localizedBridgeLeaveTip()}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: cs.onSurface.withValues(alpha: 0.85),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 3: 日期间隔 / 日期加减推算 / 公农历（含闰月）互转
// ---------------------------------------------------------------------------
class _DateToolsTab extends StatefulWidget {
  final DateTime initialDate;
  final DateTime? initialSecondDate;
  final ValueChanged<DateTime> onOpenAlmanac;

  const _DateToolsTab({
    required this.initialDate,
    required this.initialSecondDate,
    required this.onOpenAlmanac,
  });

  @override
  State<_DateToolsTab> createState() => _DateToolsTabState();
}

class _DateToolsTabState extends State<_DateToolsTab> {
  // (a) Interval state
  late DateTime _intervalStart;
  late DateTime _intervalEnd;
  bool _inclusive = false;

  // (b) Offset state
  late DateTime _offsetBase;
  late final TextEditingController _offsetController;
  bool _offsetWorkdaysOnly = false;

  // (c) Solar <-> Lunar converter state
  bool _solarToLunarMode = true;
  late DateTime _convSolar;
  int _convLunarYear = 2025;
  int _convLunarMonth = 6;
  int _convLunarDay = 1;
  bool _convIsLeap = false;

  @override
  void initState() {
    super.initState();
    _intervalStart = _clampSupportedSolar(widget.initialDate);
    _intervalEnd = _clampSupportedSolar(
      widget.initialSecondDate ??
          widget.initialDate.add(const Duration(days: 30)),
    );
    _offsetBase = _clampSupportedSolar(widget.initialDate);
    _offsetController = TextEditingController(text: '30');
    _convSolar = _clampSupportedSolar(widget.initialDate);
    final seedLunar =
        LunarCalendar.tryFromSolar(_convSolar) ?? const LunarDate(2025, 6, 1);
    _convLunarYear = seedLunar.year.clamp(1900, 2099);
    _convLunarMonth = seedLunar.month;
    _convLunarDay = seedLunar.day;
    _convIsLeap = seedLunar.isLeapMonth;
  }

  @override
  void dispose() {
    _offsetController.dispose();
    super.dispose();
  }

  Future<DateTime?> _pickSolar(DateTime current, String title) {
    return AppDatePicker.pickSolar(
      context,
      initialDate: current,
      firstDate: DateTime(1900),
      lastDate: DateTime(2099, 12, 31),
      title: title,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final surfaceStyle = appSurfaceStyleOf(context);
    final cardRadius = surfaceStyle?.cardRadius ?? DesignTokens.radiusCard;
    final tileRadius = surfaceStyle?.smallTileRadius ?? DesignTokens.radiusControl;
    final holidayColor = AlmanacPalette.holidayTeal(isDark: isDark);
    final makeupColor = AlmanacPalette.makeupIndigo(isDark: isDark);
    final interval = AlmanacToolsService.calculateDateInterval(
      _intervalStart,
      _intervalEnd,
      inclusive: _inclusive,
    );
    final delta = int.tryParse(_offsetController.text.trim()) ?? 0;
    final safeDelta = delta.clamp(-36500, 36500).toInt();
    final offsetResult = AlmanacToolsService.offsetDate(
      _offsetBase,
      safeDelta,
      workdaysOnly: _offsetWorkdaysOnly,
    );

    final leapOfYear = LunarCalendar.leapMonthOfLunarYear(_convLunarYear);
    final effectiveIsLeap = _convIsLeap && leapOfYear == _convLunarMonth;
    final maxLunarDay = (() {
      final d = LunarCalendar.daysInLunarMonth(
        _convLunarYear,
        _convLunarMonth,
        isLeap: effectiveIsLeap,
      );
      return d > 0 ? d : 29;
    })();
    final safeLunarDay = _convLunarDay.clamp(1, maxLunarDay).toInt();

    final conversionDetail = _solarToLunarMode
        ? AlmanacToolsService.solarToLunarDetail(_convSolar)
        : AlmanacToolsService.lunarToSolarDetail(
            _convLunarYear,
            _convLunarMonth,
            safeLunarDay,
            isLeap: effectiveIsLeap,
          );

    return Scrollbar(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          14,
          12,
          14,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // (a) Interval calculator
                AppSurfaceCard(
                  key: const ValueKey('date_interval_card'),
                  padding: const EdgeInsets.all(14),
                  borderRadius: BorderRadius.circular(cardRadius),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.18),
                    width: 0.45,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AlmanacUiCopy.intervalCalcTitle,
                        style: TextStyle(
                          fontSize: 15,
                          color: cs.onSurface,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ActionChip(
                            key: const ValueKey('interval_start_picker'),
                            label: Text(
                              '${AlmanacUiCopy.startDateLabel}: ${AppDateFormat.date(context, _intervalStart)}',
                            ),
                            side: BorderSide(
                              color: cs.outlineVariant.withValues(alpha: 0.35),
                              width: 0.45,
                            ),
                            onPressed: () async {
                              final p = await _pickSolar(
                                _intervalStart,
                                AlmanacUiCopy.startDateLabel,
                              );
                              if (!mounted || p == null) return;
                              setState(() => _intervalStart = p);
                            },
                          ),
                          IconButton(
                            tooltip: 'Swap',
                            onPressed: () {
                              setState(() {
                                final tmp = _intervalStart;
                                _intervalStart = _intervalEnd;
                                _intervalEnd = tmp;
                              });
                            },
                            icon: const Icon(Icons.swap_horiz_rounded, size: 20),
                          ),
                          ActionChip(
                            key: const ValueKey('interval_end_picker'),
                            label: Text(
                              '${AlmanacUiCopy.endDateLabel}: ${AppDateFormat.date(context, _intervalEnd)}',
                            ),
                            side: BorderSide(
                              color: cs.outlineVariant.withValues(alpha: 0.35),
                              width: 0.45,
                            ),
                            onPressed: () async {
                              final p = await _pickSolar(
                                _intervalEnd,
                                AlmanacUiCopy.endDateLabel,
                              );
                              if (!mounted || p == null) return;
                              setState(() => _intervalEnd = p);
                            },
                          ),
                          FilterChip(
                            selected: _inclusive,
                            label: Text(AlmanacUiCopy.includeEndDateLabel),
                            selectedColor: cs.primary.withValues(alpha: 0.14),
                            side: BorderSide(
                              color: cs.outlineVariant.withValues(alpha: 0.35),
                              width: 0.45,
                            ),
                            onSelected: (v) => setState(() => _inclusive = v),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _MetricPill(
                            key: const ValueKey('interval_calendar_days'),
                            label: AlmanacUiCopy.calendarDaysLabel,
                            value: '${interval.calendarDays}',
                            color: cs.primary,
                          ),
                          _MetricPill(
                            label: AlmanacUiCopy.workdaysLabel,
                            value: '${interval.workdays}',
                            color: AlmanacPalette.workdayBlue(isDark: isDark),
                          ),
                          _MetricPill(
                            label: AlmanacUiCopy.restDaysLabel,
                            value: '${interval.restDays}',
                            color: holidayColor,
                          ),
                          _MetricPill(
                            label: AlmanacUiCopy.weekendDaysLabel,
                            value: '${interval.weekendDays}',
                            color: AlmanacPalette.termGreen(isDark: isDark),
                          ),
                          _MetricPill(
                            label: AlmanacUiCopy.holidayDaysLabel,
                            value: '${interval.holidayDays}',
                            color: AlmanacPalette.sanFuOrange(isDark: isDark),
                          ),
                          _MetricPill(
                            label: AlmanacUiCopy.makeupDaysLabel,
                            value: '${interval.makeupWorkdays}',
                            color: makeupColor,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // (b) Offset calculator
                AppSurfaceCard(
                  key: const ValueKey('date_offset_card'),
                  padding: const EdgeInsets.all(14),
                  borderRadius: BorderRadius.circular(cardRadius),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.18),
                    width: 0.45,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AlmanacUiCopy.offsetCalcTitle,
                        style: TextStyle(
                          fontSize: 15,
                          color: cs.onSurface,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ActionChip(
                            label: Text(
                              '${AlmanacUiCopy.baseDateLabel}: ${AppDateFormat.date(context, _offsetBase)}',
                            ),
                            side: BorderSide(
                              color: cs.outlineVariant.withValues(alpha: 0.35),
                              width: 0.45,
                            ),
                            onPressed: () async {
                              final p = await _pickSolar(
                                _offsetBase,
                                AlmanacUiCopy.baseDateLabel,
                              );
                              if (!mounted || p == null) return;
                              setState(() => _offsetBase = p);
                            },
                          ),
                          SizedBox(
                            width: 150,
                            child: TextField(
                              key: const ValueKey('date_offset_input'),
                              controller: _offsetController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    signed: true,
                                  ),
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                isDense: true,
                                labelText: AlmanacUiCopy.deltaDaysLabel,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                    DesignTokens.radiusControl,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          FilterChip(
                            key: const ValueKey('date_offset_workdays_chip'),
                            selected: _offsetWorkdaysOnly,
                            label: Text(AlmanacUiCopy.workdaysOnlyLabel),
                            selectedColor: cs.primary.withValues(alpha: 0.14),
                            side: BorderSide(
                              color: cs.outlineVariant.withValues(alpha: 0.35),
                              width: 0.45,
                            ),
                            onSelected: (v) =>
                                setState(() => _offsetWorkdaysOnly = v),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final d in const [-30, -7, 7, 30, 90, 100])
                            ActionChip(
                              visualDensity: VisualDensity.compact,
                              label: Text(d > 0 ? '+$d' : '$d'),
                              side: BorderSide(
                                color: cs.outlineVariant.withValues(alpha: 0.30),
                                width: 0.45,
                              ),
                              onPressed: () {
                                _offsetController.text = '$d';
                                setState(() {});
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(tileRadius),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${AlmanacUiCopy.targetDateLabel}: ${AlmanacUiCopy.fullDateTitle(offsetResult.targetDate, null, AppDateFormat.patternOf(context))}',
                                    key: const ValueKey('date_offset_result'),
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: cs.onSurface,
                                      fontWeight: FontWeight.normal,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: [
                                      if (offsetResult.lunarDate != null)
                                        _ToolPill(
                                          text:
                                              AlmanacLocaleFormat.formatLunarDate(
                                                offsetResult.lunarDate!,
                                              ),
                                          color: cs.primary,
                                        ),
                                      _ToolPill(
                                        text: AlmanacUiCopy.isoWeekBadge(
                                          offsetResult.isoWeekNumber,
                                        ),
                                        color: cs.secondary,
                                      ),
                                      if (offsetResult.isHoliday)
                                        _ToolPill(
                                          text: offsetResult.holidayName ??
                                              AlmanacUiCopy.holidayBadge,
                                          color: holidayColor,
                                        ),
                                      if (offsetResult.isWorkMakeupDay)
                                        _ToolPill(
                                          text:
                                              AlmanacUiCopy.makeupWorkdayBadge,
                                          color: makeupColor,
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: AlmanacUiCopy.openAlmanacLabel,
                              onPressed: () => widget.onOpenAlmanac(
                                offsetResult.targetDate,
                              ),
                              icon: Icon(
                                Icons.open_in_new_rounded,
                                size: 18,
                                color: cs.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // (c) Standalone Solar <-> Lunar Converter (active leap month support)
                AppSurfaceCard(
                  key: const ValueKey('solar_lunar_converter_card'),
                  padding: const EdgeInsets.all(14),
                  borderRadius: BorderRadius.circular(cardRadius),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.18),
                    width: 0.45,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AlmanacUiCopy.solarLunarConverterTitle,
                        style: TextStyle(
                          fontSize: 15,
                          color: cs.onSurface,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SegmentedButton<bool>(
                        key: const ValueKey('converter_mode_segmented'),
                        segments: [
                          ButtonSegment(
                            value: true,
                            label: Text(AlmanacUiCopy.solarToLunarTab),
                          ),
                          ButtonSegment(
                            value: false,
                            label: Text(AlmanacUiCopy.lunarToSolarTab),
                          ),
                        ],
                        selected: {_solarToLunarMode},
                        onSelectionChanged: (s) =>
                            setState(() => _solarToLunarMode = s.first),
                      ),
                      const SizedBox(height: 12),
                      if (_solarToLunarMode)
                        ActionChip(
                          key: const ValueKey('converter_solar_date_chip'),
                          avatar: Icon(
                            Icons.calendar_month_outlined,
                            size: 16,
                            color: cs.primary,
                          ),
                          label: Text(AppDateFormat.date(context, _convSolar)),
                          side: BorderSide(
                            color: cs.outlineVariant.withValues(alpha: 0.35),
                            width: 0.45,
                          ),
                          onPressed: () async {
                            final p = await _pickSolar(
                              _convSolar,
                              AlmanacUiCopy.solarToLunarTab,
                            );
                            if (!mounted || p == null) return;
                            setState(() => _convSolar = p);
                          },
                        )
                      else
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                _DropdownSelector<int>(
                                  key: const ValueKey('converter_lunar_year'),
                                  value: _convLunarYear,
                                  items: List.generate(200, (i) => 1900 + i),
                                  labelBuilder: (y) =>
                                      AlmanacLocaleFormat.formatLunarYear(y),
                                  onChanged: (y) {
                                    setState(() {
                                      _convLunarYear = y;
                                      final lm =
                                          LunarCalendar.leapMonthOfLunarYear(y);
                                      if (lm != _convLunarMonth) {
                                        _convIsLeap = false;
                                      }
                                    });
                                  },
                                ),
                                _DropdownSelector<int>(
                                  key: const ValueKey('converter_lunar_month'),
                                  value: _convLunarMonth,
                                  items: List.generate(12, (i) => i + 1),
                                  labelBuilder: (m) => AlmanacUiCopy.isEn
                                      ? 'Month $m'
                                      : LunarCalendar.monthName(m),
                                  onChanged: (m) {
                                    setState(() {
                                      _convLunarMonth = m;
                                      if (leapOfYear != m) {
                                        _convIsLeap = false;
                                      }
                                    });
                                  },
                                ),
                                _DropdownSelector<int>(
                                  key: const ValueKey('converter_lunar_day'),
                                  value: safeLunarDay,
                                  items: List.generate(
                                    maxLunarDay,
                                    (i) => i + 1,
                                  ),
                                  labelBuilder: (d) => AlmanacUiCopy.isEn
                                      ? 'Day $d'
                                      : LunarCalendar.dayName(d),
                                  onChanged: (d) =>
                                      setState(() => _convLunarDay = d),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (leapOfYear > 0)
                              FilterChip(
                                key: const ValueKey(
                                  'converter_leap_month_switch',
                                ),
                                selected: effectiveIsLeap,
                                label: Text(
                                  AlmanacUiCopy.isEn
                                      ? '${AlmanacUiCopy.isLeapMonthLabel} · Month $leapOfYear'
                                      : '${AlmanacUiCopy.isLeapMonthLabel} · ${LunarCalendar.monthName(leapOfYear, isLeap: true)}',
                                ),
                                selectedColor: cs.primary.withValues(alpha: 0.14),
                                side: BorderSide(
                                  color: cs.outlineVariant.withValues(
                                    alpha: 0.35,
                                  ),
                                  width: 0.45,
                                ),
                                onSelected: (selected) {
                                  setState(() {
                                    if (selected) {
                                      _convLunarMonth = leapOfYear;
                                    }
                                    _convIsLeap = selected;
                                  });
                                },
                              )
                            else
                              Text(
                                AlmanacUiCopy.yearHasNoLeapMonth,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      const SizedBox(height: 12),
                      if (conversionDetail != null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(tileRadius),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      AlmanacUiCopy.fullDateTitle(
                                        conversionDetail.solarDate,
                                        null,
                                        AppDateFormat.patternOf(context),
                                      ),
                                      key: const ValueKey(
                                        'converter_solar_result',
                                      ),
                                      style: TextStyle(
                                        fontSize: 14.5,
                                        color: cs.onSurface,
                                        fontWeight: FontWeight.normal,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: AlmanacUiCopy.openAlmanacLabel,
                                    onPressed: () => widget.onOpenAlmanac(
                                      conversionDetail.solarDate,
                                    ),
                                    icon: Icon(
                                      Icons.open_in_new_rounded,
                                      size: 18,
                                      color: cs.primary,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                AlmanacLocaleFormat.formatFullLunarDate(
                                  conversionDetail.lunarDate,
                                  includeGanzhi: true,
                                ),
                                key: const ValueKey('converter_lunar_result'),
                                style: TextStyle(
                                  fontSize: 13.5,
                                  color: cs.primary,
                                ),
                              ),
                              if (conversionDetail.detail != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  AlmanacLocaleFormat.formatGanzhiLine(
                                    conversionDetail.detail!,
                                  ),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  _ToolPill(
                                    text: AlmanacLocaleFormat.formatZodiac(
                                      conversionDetail.zodiac,
                                    ),
                                    color: cs.primary,
                                  ),
                                  _ToolPill(
                                    text: AlmanacLocaleFormat.formatXingZuo(
                                      conversionDetail.xingZuo,
                                    ),
                                    color: cs.secondary,
                                  ),
                                  _ToolPill(
                                    text: AlmanacUiCopy.isoWeekBadge(
                                      conversionDetail.isoWeekNumber,
                                    ),
                                    color: holidayColor,
                                  ),
                                  if (conversionDetail.tianShen.isNotEmpty)
                                    _ToolPill(
                                      text:
                                          '${AlmanacLocaleFormat.formatTianShen(conversionDetail.tianShen)} (${AlmanacLocaleFormat.formatTianShenType(conversionDetail.tianShenType)})',
                                      color: AlmanacPalette.huangDaoAmber(
                                        isDark: isDark,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        )
                      else
                        Text(
                          AlmanacUiCopy.unavailable,
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 4: 24节气时刻表 & 生辰八字简排
// ---------------------------------------------------------------------------
class _SolarTermsBaziTab extends StatefulWidget {
  final DateTime initialDate;
  final ValueChanged<DateTime> onOpenAlmanac;

  const _SolarTermsBaziTab({
    required this.initialDate,
    required this.onOpenAlmanac,
  });

  @override
  State<_SolarTermsBaziTab> createState() => _SolarTermsBaziTabState();
}

class _SolarTermsBaziTabState extends State<_SolarTermsBaziTab> {
  late int _termsYear;
  late DateTime _birthDate;
  int _birthHour = 12;

  @override
  void initState() {
    super.initState();
    _termsYear = widget.initialDate.year.clamp(1900, 2099);
    _birthDate = _clampSupportedSolar(widget.initialDate);
  }

  String _formatDateTime(DateTime dt) {
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    return '${dt.year}-$m-$d $hh:$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final surfaceStyle = appSurfaceStyleOf(context);
    final cardRadius = surfaceStyle?.cardRadius ?? DesignTokens.radiusCard;
    final tileRadius = surfaceStyle?.smallTileRadius ?? DesignTokens.radiusControl;
    final termAccent = AlmanacPalette.termGreen(isDark: isDark);
    final now = DateTime.now();
    final nextTerm = LunarCalendar.nextSolarTerm(now);
    final terms = LunarCalendar.yearSolarTerms(_termsYear);
    final birthDateTime = DateTime(
      _birthDate.year,
      _birthDate.month,
      _birthDate.day,
      _birthHour,
    );
    final bazi = LunarCalendar.tryEightChar(birthDateTime);

    return Scrollbar(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          14,
          12,
          14,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // BaZi card
                AppSurfaceCard(
                  key: const ValueKey('bazi_calculator_card'),
                  padding: const EdgeInsets.all(14),
                  borderRadius: BorderRadius.circular(cardRadius),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.18),
                    width: 0.45,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AlmanacUiCopy.baziTitle,
                        style: TextStyle(
                          fontSize: 15,
                          color: cs.onSurface,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ActionChip(
                            key: const ValueKey('bazi_birth_date_chip'),
                            avatar: Icon(
                              Icons.cake_outlined,
                              size: 16,
                              color: cs.primary,
                            ),
                            label: Text(
                              '${AlmanacUiCopy.birthDateTimeLabel}: ${AppDateFormat.date(context, _birthDate)}',
                            ),
                            side: BorderSide(
                              color: cs.outlineVariant.withValues(alpha: 0.35),
                              width: 0.45,
                            ),
                            onPressed: () async {
                              final p = await AppDatePicker.pickSolar(
                                context,
                                initialDate: _birthDate,
                                firstDate: DateTime(1900),
                                lastDate: DateTime(2099, 12, 31),
                                title: AlmanacUiCopy.birthDateTimeLabel,
                              );
                              if (!mounted || p == null) return;
                              setState(() => _birthDate = p);
                            },
                          ),
                          _DropdownSelector<int>(
                            key: const ValueKey('bazi_birth_hour'),
                            value: _birthHour,
                            items: List.generate(24, (i) => i),
                            labelBuilder: (h) =>
                                '${h.toString().padLeft(2, '0')}:00',
                            onChanged: (h) => setState(() => _birthHour = h),
                          ),
                        ],
                      ),
                      if (bazi != null) ...[
                        const SizedBox(height: 12),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final narrow = constraints.maxWidth < 460;
                            final pillars = [
                              (
                                AlmanacUiCopy.yearPillarLabel,
                                bazi.yearGanZhi,
                                bazi.yearWuXing,
                                bazi.yearNaYin,
                              ),
                              (
                                AlmanacUiCopy.monthPillarLabel,
                                bazi.monthGanZhi,
                                bazi.monthWuXing,
                                bazi.monthNaYin,
                              ),
                              (
                                AlmanacUiCopy.dayPillarLabel,
                                bazi.dayGanZhi,
                                bazi.dayWuXing,
                                bazi.dayNaYin,
                              ),
                              (
                                AlmanacUiCopy.timePillarLabel,
                                bazi.timeGanZhi,
                                bazi.timeWuXing,
                                bazi.timeNaYin,
                              ),
                            ];
                            return GridView.count(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              crossAxisCount: narrow ? 2 : 4,
                              mainAxisSpacing: 8,
                              crossAxisSpacing: 8,
                              childAspectRatio: narrow ? 1.85 : 1.18,
                              children: [
                                for (final p in pillars)
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: cs.primary.withValues(alpha: 0.06),
                                      borderRadius: BorderRadius.circular(
                                        tileRadius,
                                      ),
                                      border: Border.all(
                                        color: cs.primary.withValues(
                                          alpha: 0.16,
                                        ),
                                        width: 0.45,
                                      ),
                                    ),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          p.$1,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: cs.onSurfaceVariant,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          AlmanacLocaleFormat.formatGanZhi(
                                            p.$2,
                                          ),
                                          style: TextStyle(
                                            fontSize: 16,
                                            color: cs.primary,
                                            fontWeight: FontWeight.normal,
                                          ),
                                        ),
                                        Text(
                                          '${AlmanacLocaleFormat.formatWuXing(p.$3)} · ${AlmanacLocaleFormat.formatNaYin(p.$4)}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            color: cs.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _ToolPill(
                              text: AlmanacLocaleFormat.formatZodiac(bazi.zodiac),
                              color: cs.primary,
                            ),
                            _ToolPill(
                              text:
                                  '${AlmanacUiCopy.dayMasterLabel}: ${bazi.dayMaster} (${AlmanacLocaleFormat.formatWuXing(bazi.dayMasterWuXing)})',
                              color: AlmanacPalette.huangDaoAmber(
                                isDark: isDark,
                              ),
                            ),
                            _ToolPill(
                              text:
                                  '${AlmanacUiCopy.wuXingSummaryLabel}: ${bazi.wuXingCounts.entries.map((e) => '${AlmanacLocaleFormat.formatWuXing(e.key)} ${e.value}').join(' · ')}',
                              color: AlmanacPalette.holidayTeal(
                                isDark: isDark,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // 24 Solar Terms Card
                AppSurfaceCard(
                  key: const ValueKey('solar_terms_24_card'),
                  padding: const EdgeInsets.all(14),
                  borderRadius: BorderRadius.circular(cardRadius),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.18),
                    width: 0.45,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              AlmanacUiCopy.yearSolarTermsTitle,
                              style: TextStyle(
                                fontSize: 15,
                                color: cs.onSurface,
                                fontWeight: FontWeight.normal,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: _termsYear <= 1900
                                ? null
                                : () => setState(() => _termsYear--),
                            icon: const Icon(Icons.chevron_left, size: 20),
                          ),
                          Text(
                            AlmanacUiCopy.yearHeader(_termsYear),
                            style: TextStyle(
                              fontSize: 13.5,
                              color: cs.primary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: _termsYear >= 2099
                                ? null
                                : () => setState(() => _termsYear++),
                            icon: const Icon(Icons.chevron_right, size: 20),
                          ),
                        ],
                      ),
                      if (nextTerm != null)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(top: 6, bottom: 10),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: termAccent.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(
                              DesignTokens.radiusSm,
                            ),
                          ),
                          child: Text(
                            '${AlmanacUiCopy.nextSolarTermLabel}: ${AlmanacUiCopy.solarTermCountdownText(nextTerm)} (${_formatDateTime(nextTerm.exactDateTime)})',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                              color: appReadableForeground(
                                Color.alphaBlend(
                                  termAccent.withValues(alpha: 0.08),
                                  cs.surface,
                                ),
                                AlmanacPalette.auspiciousGreen(isDark: isDark),
                              ),
                            ),
                          ),
                        ),
                      for (final term in terms)
                        InkWell(
                          onTap: () => widget.onOpenAlmanac(term.exactDateTime),
                          borderRadius: BorderRadius.circular(
                            DesignTokens.radiusSm,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                _ToolPill(
                                  text: AlmanacLocaleFormat.formatSolarTerm(
                                        term.name,
                                      ) ??
                                      term.name,
                                  color: nextTerm != null &&
                                          term.exactDateTime ==
                                              nextTerm.exactDateTime
                                      ? cs.primary
                                      : termAccent,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _formatDateTime(term.exactDateTime),
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                      color: cs.onSurface.withValues(alpha: 0.86),
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  size: 16,
                                  color: cs.onSurfaceVariant,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolPill extends StatelessWidget {
  final String text;
  final Color color;

  const _ToolPill({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final adapted = AlmanacPalette.adapt(color, isDark: isDark);
    final cardBg = Color.alphaBlend(
      appSurfaceStyleOf(context)?.cardFillColor ?? cs.surface,
      isDark ? cs.surface : cs.surfaceContainerLowest,
    );
    final pillBg = Color.alphaBlend(adapted.withValues(alpha: 0.10), cardBg);
    final fg = appReadableForeground(
      pillBg,
      Color.lerp(adapted, cs.onSurface, 0.16) ?? adapted,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: adapted.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(DesignTokens.radiusPill),
        border: Border.all(
          color: adapted.withValues(alpha: 0.22),
          width: 0.45,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          color: fg,
          fontWeight: FontWeight.normal,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MetricPill({
    super.key,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final adapted = AlmanacPalette.adapt(color, isDark: isDark);
    final cardBg = Color.alphaBlend(
      appSurfaceStyleOf(context)?.cardFillColor ?? cs.surface,
      isDark ? cs.surface : cs.surfaceContainerLowest,
    );
    final pillBg = Color.alphaBlend(adapted.withValues(alpha: 0.08), cardBg);
    final fg = appReadableForeground(
      pillBg,
      Color.lerp(adapted, cs.onSurface, 0.12) ?? adapted,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: adapted.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(DesignTokens.radiusControl),
        border: Border.all(
          color: adapted.withValues(alpha: 0.18),
          width: 0.45,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              color: fg,
              fontWeight: FontWeight.normal,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}

class _DropdownSelector<T> extends StatelessWidget {
  final T value;
  final List<T> items;
  final String Function(T) labelBuilder;
  final ValueChanged<T> onChanged;

  const _DropdownSelector({
    super.key,
    required this.value,
    required this.items,
    required this.labelBuilder,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(DesignTokens.radiusSm),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.35),
          width: 0.45,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          isDense: true,
          value: value,
          style: TextStyle(
            fontSize: 13,
            color: cs.onSurface,
            fontWeight: FontWeight.normal,
          ),
          items: [
            for (final item in items)
              DropdownMenuItem<T>(
                value: item,
                child: Text(labelBuilder(item)),
              ),
          ],
          onChanged: (next) {
            if (next != null) onChanged(next);
          },
        ),
      ),
    );
  }
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime _clampSupportedSolar(DateTime d) {
  final day = _dateOnly(d);
  if (day.isBefore(DateTime(1900))) return DateTime(1900);
  if (day.isAfter(DateTime(2099, 12, 31))) return DateTime(2099, 12, 31);
  return day;
}
