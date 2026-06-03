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
    expect(source, contains('Navigator.of(context).push('));
    expect(source, isNot(contains('showModalBottomSheet<void>')));
    expect(source, isNot(contains('Widget _denseAlmanacCard({')));
    expect(source, contains('LunarCalendar.almanacDetail(selectedDate)'));
    expect(source, contains('final selectedDate = _date'));
    expect(source, contains('final lunar = almanacDetail.lunarDate'));
    expect(
      source,
      contains('final detail = LunarCalendar.almanacDetail(date)'),
    );
    final calendarIndex = source.indexOf('monthCalendar,');
    final summaryIndex = source.indexOf('summary,');
    final highlightsIndex = source.indexOf('highlights,');
    expect(calendarIndex, greaterThanOrEqualTo(0));
    expect(summaryIndex, greaterThan(calendarIndex));
    expect(highlightsIndex, greaterThan(summaryIndex));
    expect(source, contains("'\${date.year}年\${date.month}月\${date.day}日星期"));
    expect(source, contains("title: '胎神'"));
    expect(source, contains('value: detail.fetalGod'));
    expect(source, contains("title: '彭祖'"));
    expect(source, contains('value: detail.pengZu'));
    expect(source, contains("title: '五行'"));
    expect(source, contains('value: detail.fiveElements'));
    expect(source, contains("title: '星宿'"));
    expect(source, contains('value: detail.mansion'));
    expect(source, contains("title: '冲煞'"));
    expect(source, contains('value: detail.clash'));
    expect(source, contains('class _ClassicalHourRow'));
    expect(source, contains('class _ClassicalHourCell'));
    expect(source, isNot(contains('Widget _aboutCard()')));
    final monthCalendar = source.substring(
      source.indexOf('class _MonthCalendar'),
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
    expect(source, contains('onPressed: onOpenAlmanac'));
    expect(source, contains("label: const Text('查看黄历')"));
    expect(source, isNot(contains('查看全部')));
    expect(source, isNot(contains('更多')));
    expect(source, isNot(contains('_showAlmanacYijiDialog')));
    expect(source, isNot(contains('onTap: _showSelectedDateDetail')));
    expect(source, isNot(contains('onTap: onOpenAlmanac')));
    expect(source, contains('const SizedBox(width: 6)'));
    expect(
      source,
      isNot(
        contains("const SizedBox(height: 10),\n        _yijiCard(title: '忌'"),
      ),
    );
    expect(source, isNot(contains('constraints.maxWidth < 520')));
    expect(source, contains("Text(alreadyToday ? '已经是今天' : '已回到今天')"));
    expect(source, contains('messenger.hideCurrentSnackBar()'));
    expect(source, contains('behavior: SnackBarBehavior.floating'));
    expect(source, contains("tooltip: '回到今天'"));
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
