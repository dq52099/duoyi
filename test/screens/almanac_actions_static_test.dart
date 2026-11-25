import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('黄历和万年历右上角只保留有反馈的今天动作', () {
    final source = File('lib/screens/almanac_screen.dart').readAsStringSync();

    expect(source, contains('void _goToday()'));
    expect(source, contains('LayoutBuilder('));
    expect(source, contains('ConstrainedBox('));
    expect(source, contains('maxWidth: 860'));
    expect(source, contains('final wide = constraints.maxWidth >= 940'));
    expect(source, contains('return Scrollbar('));
    expect(source, contains('SingleChildScrollView('));
    expect(source, contains('class _MonthCalendar'));
    expect(source, contains('class _SelectedDateSummaryCard'));
    expect(source, contains('class _AlmanacDetailPage'));
    expect(source, contains('class _ClassicalAlmanacCard'));
    expect(source, contains('Navigator.of(context).push<DateTime?>('));
    expect(source, isNot(contains('showModalBottomSheet<void>')));
    expect(source, isNot(contains('Widget _denseAlmanacCard({')));
    expect(source, contains('LunarCalendar.tryAlmanacDetail(selectedDate)'));
    expect(source, contains('final selectedDate = _date'));
    expect(
      source,
      contains(
        'almanacDetail?.lunarDate ?? LunarCalendar.tryFromSolar(selectedDate)',
      ),
    );
    expect(
      source,
      contains('final Map<int, LunarAlmanacDetail?> _detailCache'),
    );
    expect(source, contains('LunarAlmanacDetail? _detailFor(DateTime date)'));
    expect(source, contains('() => LunarCalendar.tryAlmanacDetail(day)'));
    final pageBuilderStart = source.indexOf('itemBuilder: (context, page) {');
    final pageDetailMatch = RegExp(
      r'final\s+pageDetail\s*=\s*_detailFor\(\s*pageDate\s*\)\s*;',
    ).firstMatch(source);
    expect(pageBuilderStart, greaterThanOrEqualTo(0));
    expect(pageDetailMatch, isNotNull);
    final pageDetail = pageDetailMatch!;
    expect(pageDetail.start, greaterThan(pageBuilderStart));
    final skippedCivilBranch = source.substring(
      pageBuilderStart,
      pageDetail.start,
    );
    expect(
      skippedCivilBranch,
      matches(
        RegExp(
          r'final\s+pageDate\s*=\s*_dateForPage\(\s*page\s*\)\s*;'
          r'\s*if\s*\(\s*pageDate\s*==\s*null\s*\)\s*\{',
        ),
      ),
    );
    expect(skippedCivilBranch, contains('return Scrollbar('));
    expect(skippedCivilBranch, contains('child: _SkippedCivilDayCard('));
    expect(skippedCivilBranch, contains('_gregorianDateForPage(page)'));
    expect(skippedCivilBranch, contains('year: utcCivil.year'));
    expect(skippedCivilBranch, contains('month: utcCivil.month'));
    expect(skippedCivilBranch, contains('day: utcCivil.day'));
    expect(skippedCivilBranch, isNot(contains('_detailFor(')));
    final pageBuilderEnd = source.indexOf(
      'class _AlmanacDetailNavBar',
      pageDetail.end,
    );
    expect(pageBuilderEnd, greaterThan(pageDetail.end));
    final normalCivilBranch = source.substring(pageDetail.end, pageBuilderEnd);
    expect(normalCivilBranch, contains('_ClassicalAlmanacCard('));
    expect(normalCivilBranch, contains('detail: pageDetail'));
    expect(normalCivilBranch, contains('date: pageDate'));
    expect(normalCivilBranch, contains('_AlmanacExtendedDetailsSection('));
    final calendarIndex = source.indexOf('monthCalendar,');
    final summaryIndex = source.indexOf('summary,');
    final highlightsIndex = source.indexOf('highlights,');
    expect(calendarIndex, greaterThanOrEqualTo(0));
    expect(summaryIndex, greaterThan(calendarIndex));
    expect(highlightsIndex, greaterThan(summaryIndex));
    final copy = File('lib/core/almanac_ui_copy.dart').readAsStringSync();
    final fullDateCopyStart = copy.indexOf('static String fullDateTitle(');
    final fullDateCopyEnd = copy.indexOf('static String skippedCivilDayTitle(');
    expect(fullDateCopyStart, greaterThanOrEqualTo(0));
    expect(fullDateCopyEnd, greaterThan(fullDateCopyStart));
    final fullDateCopy = copy.substring(fullDateCopyStart, fullDateCopyEnd);
    expect(fullDateCopy, contains('(locale ?? I18n.current) == AppLocale.en'));
    expect(fullDateCopy, contains('if (!isEnglish)'));
    expect(
      fullDateCopy,
      matches(
        RegExp(
          r'I18nDateFormat\.date\(\s*date\s*,\s*pattern:\s*pattern\s*,'
          r'\s*locale:\s*locale\s*,?\s*\)',
        ),
      ),
    );
    expect(fullDateCopy, contains(r'星期${weekNames[date.weekday - 1]}'));
    expect(fullDateCopy, contains(r' · ${_enWeekday(date.weekday)}'));
    expect(
      source,
      matches(
        RegExp(
          r'final\s+title\s*=\s*_selectedDate\s*!=\s*null\s*'
          r'\?\s*AlmanacUiCopy\.fullDateTitle\(\s*_selectedDate!\s*,\s*'
          r'null\s*,\s*AppDateFormat\.patternOf\(\s*context\s*\)\s*,?\s*\)',
        ),
      ),
    );
    expect(source, contains("title: '胎神'"));
    expect(source, contains('detail?.fetalGod ?? AlmanacUiCopy.unavailable'));
    expect(source, contains("title: '彭祖'"));
    expect(source, contains('detail?.pengZu ?? AlmanacUiCopy.unavailable'));
    expect(source, contains("title: '五行'"));
    expect(
      source,
      contains('detail?.fiveElements ?? AlmanacUiCopy.unavailable'),
    );
    expect(source, contains("title: '星宿'"));
    expect(source, contains('detail?.mansion ?? AlmanacUiCopy.unavailable'));
    expect(source, contains("title: '冲煞'"));
    expect(source, contains('detail?.clash ?? AlmanacUiCopy.unavailable'));
    expect(source, contains('class _ClassicalHourRow'));
    expect(source, contains('class _ClassicalHourCell'));
    expect(source, isNot(contains('Widget _aboutCard()')));
    final monthCalendar = source.substring(
      source.indexOf('class _MonthCalendar extends StatelessWidget'),
      source.indexOf('class _MonthNavButton'),
    );
    expect(monthCalendar, isNot(contains('return AppSurfaceCard(')));
    expect(monthCalendar, contains('return Column('));
    expect(source, contains('class _MonthNavButton'));
    expect(source, contains('class _SoftAlmanacTag'));
    expect(source, contains('class _ClassicalInfoTable'));
    expect(source, contains('class _ClassicalInfoCell'));
    expect(source, contains('class _VerticalYijiPanel'));
    expect(source, contains('class _VerticalYijiColumn'));
    expect(source, contains("title: '宜'"));
    expect(source, contains('terms: suitableTerms'));
    expect(source, contains("title: '忌'"));
    expect(source, contains('terms: avoidTerms'));
    expect(source, contains('onOpenAlmanac: _showSelectedDateDetail'));
    expect(source, contains("ValueKey('selected_date_almanac_summary_card')"));
    expect(source, contains('onTap: onOpenAlmanac'));
    expect(source, isNot(contains("label: const Text('查看黄历')")));
    expect(source, isNot(contains('onPressed: onOpenAlmanac')));
    expect(source, isNot(contains('查看全部')));
    expect(source, isNot(contains('更多')));
    expect(source, isNot(contains('_showAlmanacYijiDialog')));
    expect(source, isNot(contains('onTap: _showSelectedDateDetail')));
    expect(source, contains('static const int _visibleTermLimit = 5'));
    expect(source, contains('_splitAlmanacTerms('));
    expect(
      source,
      matches(
        RegExp(
          r'\.take\(_visibleTermLimit\)\.toList\(\s*growable: false,?\s*\)',
        ),
      ),
    );
    expect(source, contains("ValueKey('almanac_vertical_suitable_column')"));
    expect(
      source,
      contains("ValueKey('almanac_vertical_\${keyName}_terms_box')"),
    );
    expect(source, contains('const SizedBox(width: 10)'));
    expect(source, contains('class _VerticalTerm'));
    expect(
      source,
      isNot(
        contains("const SizedBox(height: 10),\n        _yijiCard(title: '忌'"),
      ),
    );
    expect(source, isNot(contains('constraints.maxWidth < 520')));
    final goTodayStart = source.indexOf('void _goToday()');
    expect(goTodayStart, greaterThanOrEqualTo(0));
    final goTodayEnd = source.indexOf('void _shiftMonth(', goTodayStart);
    expect(goTodayEnd, greaterThan(goTodayStart));
    final goToday = source.substring(goTodayStart, goTodayEnd);
    expect(
      goToday,
      matches(
        RegExp(
          r'ValueListenableBuilder<AppLocale>\(\s*'
          r'valueListenable:\s*I18n\.localeListenable\s*,\s*'
          r'builder:\s*\(\s*context\s*,\s*locale\s*,\s*_\s*\)\s*=>\s*'
          r'Text\(\s*AlmanacUiCopy\.goTodayFeedback\(\s*'
          r'alreadyToday:\s*alreadyToday\s*,\s*locale:\s*locale\s*,?\s*\)',
        ),
      ),
    );
    expect(source, contains('messenger.hideCurrentSnackBar()'));
    expect(source, contains('behavior: SnackBarBehavior.floating'));
    expect(source, contains("tooltip: AlmanacUiCopy.todayTooltip"));
    expect(source, isNot(contains('class _SeasonalWeatherCard')));
    expect(source, isNot(contains('class _SeasonalWeatherInfo')));
    expect(source, isNot(contains('_seasonalWeatherInfo(DateTime date)')));
    expect(source, isNot(contains('夏季天气参考')));
    expect(source, isNot(contains('补水防晒')));
    expect(source, isNot(contains('OpenMeteoAlmanacWeatherClient')));
    expect(source, isNot(contains('AlmanacWeatherClient')));
    expect(source, isNot(contains('weather')));
    expect(source, isNot(contains('Weather')));
    expect(source, isNot(contains('Icons.wb_sunny')));
    expect(source, isNot(contains('Icons.cloud')));
    expect(source, isNot(contains('Icons.water_drop')));
    expect(source, isNot(contains("import '../models/diary_entry.dart';")));
    expect(
      source,
      isNot(contains("import '../providers/diary_provider.dart';")),
    );
    expect(source, isNot(contains('context.watch<DiaryProvider?>()')));
    expect(source, isNot(contains('entryForDate(date)?.weather')));
    expect(source, isNot(contains('static List<String> _weatherDetails')));
    expect(
      source,
      isNot(contains('static List<(IconData, String)> _weatherSignals')),
    );
    expect(source, isNot(contains("'本地天气摘要'")));
    expect(source, isNot(contains("'已记录天气'")));
    expect(source, isNot(contains('来自当天日记记录')));
    expect(source, isNot(contains('当前未接入外部天气 API')));
    expect(
      source,
      isNot(contains('showDiaryEditor(context, initialDate: date)')),
    );
    expect(source, isNot(contains("label: const Text('记录天气')")));
    expect(source, isNot(contains("'高温防晒'")));
    expect(source, isNot(contains('void _toggleMode()')));
    expect(source, isNot(contains("tooltip: isAlmanac ? '切换到万年历' : '切换到黄历'")));
    expect(source, isNot(contains('Navigator.pushReplacement(')));
  });
}
